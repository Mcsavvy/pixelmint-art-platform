;; PixelMint Art Platform
;; A smart contract for minting, trading, and managing pixel art NFTs on the Stacks blockchain.
;; This contract allows artists to mint pixel art as NFTs, set royalties, and ensures proper
;; compensation on secondary sales while maintaining provenance and ownership records.

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

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-PIXELS-DATA-LENGTH u16384) ;; Limits the size of pixel data
(define-constant MAX-ROYALTY-PERCENTAGE u30)    ;; Maximum royalty percentage (30%)
(define-constant PLATFORM-FEE-PERCENTAGE u5)    ;; 5% platform fee

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

;; Keep track of the next token ID to be assigned
(define-data-var next-token-id uint u1)

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