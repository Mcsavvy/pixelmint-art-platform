```clarity
;; PixelMint Art Platform
;; A smart contract for minting, trading, and managing pixel art NFTs on the Stacks blockchain.
;; This contract allows artists to mint pixel art as NFTs, set royalties, and ensures proper
;; compensation on secondary sales while maintaining provenance and ownership records.
;; The platform also includes social features for following artists, favoriting artworks,
;; commenting on artwork, and receiving notifications about relevant platform activities.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-NOT-REGISTERED (err u102))
(define-constant ERR-INVALID-DIMENSIONS (err u103))
(define-constant ERR-NFT-NOT-FOUND (err u104))
(define-constant ERR-NOT-OWNER (err u105))
(define-constant ERR-TRANSFER-FAILED (err u106))
(define-constant ERR-INVALID-ROYALTY (err u107))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u108))
(define-constant ERR-SALE-NOT-ACTIVE (err u109))
(define-constant ERR-SELF-TRANSFER (err u110))
(define-constant ERR-ALREADY-FOLLOWING (err u111))
(define-constant ERR-NOT-FOLLOWING (err u112))
(define-constant ERR-ALREADY-FAVORITED (err u113))
(define-constant ERR-COMMENT-TOO-LONG (err u114))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-PIXELS-DATA-LENGTH u16384) ;; Limits the size of pixel data
(define-constant MAX-ROYALTY-PERCENTAGE u30)    ;; Maximum royalty percentage (30%)
(define-constant PLATFORM-FEE-PERCENTAGE u5)    ;; 5% platform fee
(define-constant MAX-COMMENT-LENGTH u500)       ;; Maximum length for comments

;; Data structures

;; Artist registry - tracks registered artists and their information
(define-map artists 
  { artist: principal }
  { username: (string-ascii 50), 
    bio: (string-utf8 500), 
    registered-at: uint }
)

;; Artwork information - stores metadata about each NFT
(define-map artworks 
  { token-id: uint }
  { title: (string-utf8 100),
    description: (string-utf8 500),
    pixel-data: (string-ascii 16384),  ;; Base64 encoded pixel data
    width: uint,
    height: uint, 
    color-palette: (string-ascii 500), ;; JSON string describing the color palette
    creator: principal,
    royalty-percentage: uint,
    created-at: uint,
    additional-metadata: (optional (string-utf8 1000)) }
)

;; Ownership records - tracks current owners of NFTs
(define-map token-owners
  { token-id: uint }
  { owner: principal }
)

;; Active sales - tracks NFTs currently listed for sale
(define-map nft-sales
  { token-id: uint }
  { price: uint,
    seller: principal,
    active: bool }
)

;; NFT ownership count - tracks how many NFTs each user owns
(define-map ownership-count
  { owner: principal }
  { count: uint }
)

;; Social Follow Graph - tracks who is following whom
(define-map follows
  { follower: principal, following: principal }
  { timestamp: uint }
)

;; User Followers Count - tracks how many followers a user has
(define-map follower-count
  { user: principal }
  { count: uint }
)

;; User Following Count - tracks how many users a user is following
(define-map following-count
  { user: principal }
  { count: uint }
)

;; Favorites - tracks which artworks a user has favorited
(define-map favorites
  { user: principal, token-id: uint }
  { timestamp: uint }
)

;; Artwork Favorite Count - tracks how many favorites an artwork has
(define-map artwork-favorite-count
  { token-id: uint }
  { count: uint }
)

;; Comments - stores user comments on artworks
(define-map comments
  { comment-id: uint }
  { token-id: uint,
    commenter: principal,
    content: (string-utf8 500),
    timestamp: uint }
)

;; Artwork Comments - tracks comment IDs associated with each artwork
(define-map artwork-comments
  { token-id: uint }
  { comment-ids: (list 100 uint) }
)

;; Notifications - stores notifications for users
(define-map notifications
  { notification-id: uint }
  { recipient: principal,
    notification-type: (string-ascii 20),
    related-token-id: (optional uint),
    related-user: (optional principal),
    read: bool,
    timestamp: uint,
    content: (string-utf8 200) }
)

;; User Notifications - tracks notification IDs for each user
(define-map user-notifications
  { user: principal }
  { notification-ids: (list 50 uint) }
)

;; Keep track of the next token ID to be assigned
(define-data-var next-token-id uint u1)

;; Keep track of the next comment ID
(define-data-var next-comment-id uint u1)

;; Keep track of the next notification ID
(define-data-var next-notification-id uint u1)

;; Private functions

;; Calculate royalty amount based on sale price and royalty percentage
(define-private (calculate-royalty (price uint) (royalty-percentage uint))
  (/ (* price royalty-percentage) u100)
)

;; Calculate platform fee
(define-private (calculate-platform-fee (price uint))
  (/ (* price PLATFORM-FEE-PERCENTAGE) u100)
)

;; Update ownership count when NFTs are transferred
(define-private (update-ownership-count (from principal) (to principal))
  (let ((from-count (default-to u0 (get count (map-get? ownership-count {owner: from})))))
    ;; Decrease previous owner's count
    (if (> from-count u0)
      (map-set ownership-count {owner: from} {count: (- from-count u1)})
      true
    )
  )
  
  ;; Increase new owner's count
  (let ((to-count (default-to u0 (get count (map-get? ownership-count {owner: to})))))
    (map-set ownership-count {owner: to} {count: (+ to-count u1)})
  )
)

;; Transfer NFT ownership internally
(define-private (transfer-ownership (token-id uint) (sender principal) (recipient principal))
  (let ((token-owner (get owner (default-to {owner: sender} (map-get? token-owners {token-id: token-id})))))
    (if (or 
          (not (is-eq token-owner sender))
          (is-eq sender recipient)
        )
      ERR-NOT-AUTHORIZED
      (begin
        (map-set token-owners {token-id: token-id} {owner: recipient})
        (update-ownership-count sender recipient)
        (ok true)
      )
    )
  )
)

;; Validate dimensions for pixel art
(define-private (validate-dimensions (width uint) (height uint))
  (if (and (> width u0) (> height u0) (<= (* width height) MAX-PIXELS-DATA-LENGTH))
    true
    false
  )
)

;; Create a notification for a user
(define-private (create-notification 
  (recipient principal) 
  (notification-type (string-ascii 20)) 
  (related-token-id (optional uint)) 
  (related-user (optional principal))
  (content (string-utf8 200))
)
  (let ((notification-id (var-get next-notification-id))
        (user-notifs (default-to {notification-ids: (list)} (map-get? user-notifications {user: recipient}))))
    
    ;; Store the notification
    (map-set notifications
      {notification-id: notification-id}
      {
        recipient: recipient,
        notification-type: notification-type,
        related-token-id: related-token-id,
        related-user: related-user,
        read: false,
        timestamp: block-height,
        content: content
      }
    )
    
    ;; Add notification to user's list
    (map-set user-notifications
      {user: recipient}
      {notification-ids: (unwrap-panic (as-max-len? (append (get notification-ids user-notifs) notification-id) u50))}
    )
    
    ;; Increment notification ID counter
    (var-set next-notification-id (+ notification-id u1))
    
    (ok notification-id)
  )
)

;; Notify followers about a new artwork
(define-private (notify-followers (artist principal) (token-id uint) (artwork-title (string-utf8 100)))
  (let ((artist-info (map-get? artists {artist: artist})))
    (if (is-some artist-info)
      (let ((username (get username (unwrap-panic artist-info))))
        ;; Notification would be sent to all followers here
        ;; This is a simplified implementation
        (ok true)
      )
      (ok false)
    )
  )
)

;; Read-only functions

;; Get artist information
(define-read-only (get-artist-info (artist principal))
  (map-get? artists {artist: artist})
)

;; Get artwork information
(define-read-only (get-artwork-info (token-id uint))
  (map-get? artworks {token-id: token-id})
)

;; Get current owner of an NFT
(define-read-only (get-token-owner (token-id uint))
  (map-get? token-owners {token-id: token-id})
)

;; Check if an NFT is for sale
(define-read-only (get-sale-info (token-id uint))
  (map-get? nft-sales {token-id: token-id})
)

;; Get number of NFTs owned by a principal
(define-read-only (get-owner-nft-count (owner principal))
  (default-to u0 (get count (map-get? ownership-count {owner: owner})))
)

;; Get the current token ID counter value
(define-read-only (get-current-token-id)
  (var-get next-token-id)
)

;; Check if user is following another user
(define-read-only (is-following (follower principal) (following principal))
  (is-some (map-get? follows {follower: follower, following: following}))
)

;; Get follower count for a user
(define-read-only (get-follower-count (user principal))
  (default-to u0 (get count (map-get? follower-count {user: user})))
)

;; Get following count for a user
(define-read-only (get-following-count (user principal))
  (default-to u0 (get count (map-get? following-count {user: user})))
)

;; Check if user has favorited an artwork
(define-read-only (has-favorited (user principal) (token-id uint))
  (is-some (map-get? favorites {user: user, token-id: token-id}))
)

;; Get favorite count for an artwork
(define-read-only (get-favorite-count (token-id uint))
  (default-to u0 (get count (map-get? artwork-favorite-count {token-id: token-id})))
)

;; Get comments for an artwork
(define-read-only (get-artwork-comment-ids (token-id uint))
  (map-get? artwork-comments {token-id: token-id})
)

;; Get a specific comment
(define-read-only (get-comment (comment-id uint))
  (map-get? comments {comment-id: comment-id})
)

;; Get notification details
(define-read-only (get-notification (notification-id uint))
  (map-get? notifications {notification-id: notification-id})
)

;; Get user's notifications
(define-read-only (get-user-notification-ids (user principal))
  (map-get? user-notifications {user: user})
)

;; Public functions

;; Register as an artist
(define-public (register-artist (username (string-ascii 50)) (bio (string-utf8 500)))
  (let ((artist tx-sender))
    (if (map-get? artists {artist: artist})
      ERR-ALREADY-REGISTERED
      (begin
        (map-set artists 
          {artist: artist} 
          {username: username, bio: bio, registered-at: block-height}
        )
        (ok true)
      )
    )
  )
)

;; Update artist profile
(define-public (update-artist-profile (username (string-ascii 50)) (bio (string-utf8 500)))
  (let ((artist tx-sender)
        (existing-artist (map-get? artists {artist: artist})))
    (if (is-none existing-artist)
      ERR-NOT-REGISTERED
      (begin
        (map-set artists 
          {artist: artist} 
          {username: username, bio: bio, registered-at: (get registered-at (unwrap-panic existing-artist))}
        )
        (ok true)
      )
    )
  )
)

;; Mint a new pixel art NFT
(define-public (mint-artwork 
  (title (string-utf8 100))
  (description (string-utf8 500))
  (pixel-data (string-ascii 16384))
  (width uint)
  (height uint)
  (color-palette (string-ascii 500))
  (royalty-percentage uint)
  (additional-metadata (optional (string-utf8 1000)))
)
  (let ((artist tx-sender)
        (new-token-id (var-get next-token-id)))
    
    ;; Validation checks
    (asserts! (map-get? artists {artist: artist}) ERR-NOT-REGISTERED)
    (asserts! (validate-dimensions width height) ERR-INVALID-DIMENSIONS)
    (asserts! (<= royalty-percentage MAX-ROYALTY-PERCENTAGE) ERR-INVALID-ROYALTY)
    
    ;; Store artwork information
    (map-set artworks
      {token-id: new-token-id}
      {
        title: title,
        description: description,
        pixel-data: pixel-data,
        width: width,
        height: height,
        color-palette: color-palette,
        creator: artist,
        royalty-percentage: royalty-percentage,
        created-at: block-height,
        additional-metadata: additional-metadata
      }
    )
    
    ;; Set initial ownership
    (map-set token-owners {token-id: new-token-id} {owner: artist})
    
    ;; Update artist's NFT count
    (let ((artist-count (default-to u0 (get count (map-get? ownership-count {owner: artist})))))
      (map-set ownership-count {owner: artist} {count: (+ artist-count u1)})
    )
    
    ;; Initialize favorite count for artwork
    (map-set artwork-favorite-count {token-id: new-token-id} {count: u0})
    
    ;; Initialize empty comments list for artwork
    (map-set artwork-comments {token-id: new-token-id} {comment-ids: (list)})
    
    ;; Notify followers about new artwork
    (notify-followers artist new-token-id title)
    
    ;; Increment token ID counter
    (var-set next-token-id (+ new-token-id u1))
    
    (ok new-token-id)
  )
)

;; List an NFT for sale
(define-public (list-for-sale (token-id uint) (price uint))
  (let ((owner tx-sender)
        (token-owner-data (map-get? token-owners {token-id: token-id})))
    
    ;; Check if NFT exists and sender is the owner
    (asserts! (is-some token-owner-data) ERR-NFT-NOT-FOUND)
    (asserts! (is-eq owner (get owner (unwrap-panic token-owner-data))) ERR-NOT-OWNER)
    (asserts! (> price u0) ERR-INSUFFICIENT-PAYMENT)
    
    ;; List NFT for sale
    (map-set nft-sales
      {token-id: token-id}
      {price: price, seller: owner, active: true}
    )
    
    (ok true)
  )
)

;; Cancel a sale listing
(define-public (cancel-sale (token-id uint))
  (let ((owner tx-sender)
        (sale-data (map-get? nft-sales {token-id: token-id})))
    
    ;; Check if NFT is for sale and sender is the seller
    (asserts! (is-some sale-data) ERR-SALE-NOT-ACTIVE)
    (asserts! (is-eq owner (get seller (unwrap-panic sale-data))) ERR-NOT-OWNER)
    
    ;; Remove sale listing
    (map-delete nft-sales {token-id: token-id})
    
    (ok true)
  )
)

;; Buy an NFT that is listed for sale
(define-public (buy-nft (token-id uint))
  (let ((buyer tx-sender)
        (sale-data (map-get? nft-sales {token-id: token-id}))
        (artwork-data (map-get? artworks {token-id: token-id})))
    
    ;; Check if NFT is for sale
    (asserts! (and (is-some sale-data) (get active (unwrap-panic sale-data))) ERR-SALE-NOT-ACTIVE)
    (asserts! (is-some artwork-data) ERR-NFT-NOT-FOUND)
    
    (let ((price (get price (unwrap-panic sale-data)))
          (seller (get seller (unwrap-panic sale-data)))
          (creator (get creator (unwrap-panic artwork-data)))
          (royalty-percentage (get royalty-percentage (unwrap-panic artwork-data))))
    
      ;; Prevent self-purchases
      (asserts! (not (is-eq buyer seller)) ERR-SELF-TRANSFER)
      
      ;; Calculate fees
      (let ((royalty-amount (calculate-royalty price royalty-percentage))
            (platform-fee (calculate-platform-fee price))
            (seller-amount (- price (+ royalty-amount platform-fee))))
        
        ;; Process payments
        ;; First pay the platform fee
        (try! (stx-transfer? platform-fee buyer CONTRACT-OWNER))
        
        ;; Then pay royalties to creator if not the seller
        (if (not (is-eq creator seller))
          (try! (stx-transfer? royalty-amount buyer creator))
          true
        )
        
        ;; Finally pay the seller
        (try! (stx-transfer? seller-amount buyer seller))
        
        ;; Transfer NFT ownership
        (try! (transfer-ownership token-id seller buyer))
        
        ;; Create notification for seller about the sale
        (create-notification 
          seller 
          "sale" 
          (some token-id) 
          (some buyer) 
          (concat "Your artwork was purchased by a collector for " (to-ascii price) " STX")
        )
        
        ;; Remove sale listing
        (map-delete nft-sales {token-id: token-id})
        
        (ok true)
      )
    )
  )
)

;; Transfer NFT to another user (not as part of a sale)
(define-public (transfer-nft (token-id uint) (recipient principal))
  (let ((sender tx-sender))
    ;; Prevent self-transfers
    (asserts! (not (is-eq sender recipient)) ERR-SELF-TRANSFER)
    
    ;; Cancel any active sale for this NFT
    (if (is-some (map-get? nft-sales {token-id: token-id}))
      (map-delete nft-sales {token-id: token-id})
      true
    )
    
    ;; Create notification for recipient
    (create-notification 
      recipient 
      "transfer" 
      (some token-id) 
      (some sender) 
      "You have received an artwork transfer")
    
    ;; Transfer ownership
    (transfer-ownership token-id sender recipient)
  )
)

;; Update artwork metadata (only allowed for certain fields and by the creator)
(define-public (update-artwork-metadata 
  (token-id uint) 
  (title (string-utf8 100)) 
  (description (string-utf8 500))
  (additional-metadata (optional (string-utf8 1000)))
)
  (let ((sender tx-sender)
        (artwork-data (map-get? artworks {token-id: token-id})))
    
    ;; Check if NFT exists
    (asserts! (is-some artwork-data) ERR-NFT-NOT-FOUND)
    
    ;; Ensure sender is the creator
    (asserts! (is-eq sender (get creator (unwrap-panic artwork-data))) ERR-NOT-AUTHORIZED)
    
    ;; Update only the allowed metadata fields
    (map-set artworks
      {token-id: token-id}
      (merge (unwrap-panic artwork-data)
             {
               title: title,
               description: description,
               additional-metadata: additional-metadata
             })
    )
    
    (ok true)
  )
)

;; Social functions

;; Follow another user
(define-public (follow-user (user-to-follow principal))
  (let ((follower tx-sender))
    ;; Prevent self-following
    (asserts! (not (is-eq follower user-to-follow)) ERR-SELF-TRANSFER)
    
    ;; Check if already following
    (asserts! (is-none (map-get? follows {follower: follower, following: user-to-follow})) ERR-ALREADY-FOLLOWING)
    
    ;; Add to follows map
    (map-set follows
      {follower: follower, following: user-to-follow}
      {timestamp: block-height}
    )
    
    ;; Update follower count for followed user
    (let ((current-follower-count (default-to u0 (get count (map-get? follower-count {user: user-to-follow})))))
      (map-set follower-count
        {user: user-to-follow}
        {count: (+ current-follower-count u1)}
      )
    )
    
    ;; Update following count for follower
    (let ((current-following-count (default-to u0 (get count (map-get? following-count {user: follower})))))
      (map-set following-count
        {user: follower}
        {count: (+ current-following-count u1)}
      )
    )
    
    ;; Create notification for followed user
    (create-notification 
      user-to-follow
      "follow"
      none
      (some follower)
      "You have a new follower"
    )
    
    (ok true)
  )
)

;; Unfollow a user
(define-public (unfollow-user (user-to-unfollow principal))
  (let ((follower tx-sender))
    ;; Check if currently following
    (asserts! (is-some (map-get? follows {follower: follower, following: user-to-unfollow})) ERR-NOT-FOLLOWING)
    
    ;; Remove from follows map
    (map-delete follows {follower: follower, following: user-to-unfollow})
    
    ;; Update follower count for unfollowed user
    (let ((current-follower-count (default-to u0 (get count (map-get? follower-count {user: user-to-unfollow})))))
      (map-set follower-count
        {user: user-to-unfollow}
        {count: (- current-follower-count u1)}
      )
    )
    
    ;; Update following count for follower
    (let ((current-following-count (default-to u0 (get count (map-get? following-count {user: follower})))))
      (map-set following-count
        {user: follower}
        {count: (- current-following-count u1)}
      )
    )
    
    (ok true)
  )
)

;; Favorite an artwork
(define-public (favorite-artwork (token-id uint))
  (let ((user tx-sender)
        (artwork-data (map-get? artworks {token-id: token-id})))
    
    ;; Check if artwork exists
    (asserts! (is-some artwork-data) ERR-NFT-NOT-FOUND)
    
    ;; Check if already favorited
    (asserts! (is-none (map-get? favorites {user: user, token-id: token-id})) ERR-ALREADY-FAVORITED)
    
    ;; Add to favorites map
    (map-set favorites
      {user: user, token-id: token-id}
      {timestamp: block-height}
    )
    
    ;; Update favorite count for artwork
    (let ((current-favorite-count (default-to u0 (get count (map-get? artwork-favorite-count {token-id: token-id})))))
      (map-set artwork-favorite-count
        {token-id: token-id}
        {count: (+ current-favorite-count u1)}
      )
    )
    
    ;; Create notification for artwork creator
    (let ((creator (get creator (unwrap-panic artwork-data))))
      (create-notification 
        creator
        "favorite"
        (some token-id)
        (some user)
        "Someone favorited your artwork"
      )
    )
    
    (ok true)
  )
)

;; Unfavorite an artwork
(define-public (unfavorite-artwork (token-id uint))
  (let ((user tx-sender)
        (artwork-data (map-get? artworks {token-id: token-id})))
    
    ;; Check if artwork exists
    (asserts! (is-some artwork-data) ERR-NFT-NOT-FOUND)
    
    ;; Check if currently favorited
    (asserts! (is-some (map-get? favorites {user: user, token-id: token-id})) ERR-NOT-AUTHORIZED)
    
    ;; Remove from favorites map
    (map-delete favorites {user: user, token-id: token-id})
    
    ;; Update favorite count for artwork
    (let ((current-favorite-count (default-to u0 (get count (map-get? artwork-favorite-count {token-id: token-id})))))
      (map-set artwork-favorite-count
        {token-id: token-id}
        {count: (- current-favorite-count u1)}
      )
    )
    
    (ok true)
  )
)

;; Add a comment to an artwork
(define-public (add-comment (token-id uint) (content (string-utf8 500)))
  (let ((user tx-sender)
        (artwork-data (map-get? artworks {token-id: token-id}))
        (comment-id (var-get next-comment-id)))
    
    ;; Check if artwork exists
    (asserts! (is-some artwork-data) ERR-NFT-NOT-FOUND)
    
    ;; Validate comment length
    (asserts! (<= (len content) MAX-COMMENT-LENGTH) ERR-COMMENT-TOO-LONG)
    
    ;; Store the comment
    (map-set comments
      {comment-id: comment-id}
      {
        token-id: token-id,
        commenter: user,
        content: content,
        timestamp: block-height
      }
    )
    
    ;; Add comment ID to artwork's comments list
    (let ((artwork-comment-data (default-to {comment-ids: (list)} (map-get? artwork-comments {token-id: token-id}))))
      (map-set artwork-comments
        {token-id: token-id}
        {comment-ids: (unwrap-panic (as-max-len? (append (get comment-ids artwork-comment-data) comment-id) u100))}
      )
    )
    
    ;; Create notification for artwork creator
    (let ((creator (get creator (unwrap-panic artwork-data))))
      (create-notification 
        creator
        "comment"
        (some token-id)
        (some user)
        "Someone commented on your artwork"
      )
    )
    
    ;; Increment comment ID counter
    (var-set next-comment-id (+ comment-id u1))
    
    (ok comment-id)
  )
)

;; Mark a notification as read
(define-public (mark-notification-read (notification-id uint))
  (let ((user tx-sender)
        (notification-data (map-get? notifications {notification-id: notification-id})))
    
    ;; Check if notification exists and belongs to user
    (asserts! (is-some notification-data) ERR-NOT-FOUND)
    (asserts! (is-eq user (get recipient (unwrap-panic notification-data))) ERR-NOT-AUTHORIZED)
    
    ;; Update notification as read
    (map-set notifications
      {notification-id: notification-id}
      (merge (unwrap-panic notification-data) {read: true})
    )
    
    (ok true)
  )
)

;; Mark all notifications as read
(define-public (mark-all-notifications-read)
  (let ((user tx-sender)
        (user-notifs (map-get? user-notifications {user: user})))
    
    ;; Check if user has notifications
    (if (is-some user-notifs)
      (begin
        ;; This is a simplified implementation
        ;; In a full implementation, we would iterate through all notifications
        ;; and mark each as read
        (ok true)
      )
      (ok false)
    )
  )
)
```