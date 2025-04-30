;; notification-registry
;;
;; This contract manages user notifications and activity feeds for the PixelMint Art Platform.
;; It tracks various platform events (artwork mints, sales, comments, follows, etc.) and
;; organizes them into personalized feeds for each user based on their preferences.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1001))
(define-constant ERR-USER-NOT-FOUND (err u1002))
(define-constant ERR-INVALID-EVENT-TYPE (err u1003))
(define-constant ERR-INVALID-PREFERENCE (err u1004))
(define-constant ERR-NOTIFICATION-NOT-FOUND (err u1005))
(define-constant ERR-NOTIFICATION-LIMIT-REACHED (err u1006))

;; Event types
(define-constant EVENT-TYPE-MINT u1)
(define-constant EVENT-TYPE-PRICE-CHANGE u2)
(define-constant EVENT-TYPE-SALE u3)
(define-constant EVENT-TYPE-COMMENT u4)
(define-constant EVENT-TYPE-FOLLOW u5)
(define-constant EVENT-TYPE-FAVORITE u6)

;; Maximum number of notifications stored per user
(define-constant MAX-NOTIFICATIONS-PER-USER u100)

;; Data maps

;; Stores notification data associated with a notification ID
;; Fields:
;; - event-type: The type of event (mint, sale, comment, etc.)
;; - actor: The principal who triggered the event
;; - target: The principal who the event is related to (can be null if not applicable)
;; - resource-id: The ID of the resource involved (artwork ID, comment ID, etc.)
;; - timestamp: When the event occurred
;; - data: Additional data about the event (price, comment text, etc.)
;; - is-read: Whether the notification has been marked as read by the user
(define-map notifications
  { notification-id: uint }
  {
    event-type: uint,
    actor: principal,
    target: (optional principal),
    resource-id: (optional uint),
    timestamp: uint,
    data: (string-ascii 256),
    is-read: bool
  }
)

;; Maps users to their notification IDs in chronological order (newest first)
(define-map user-notifications
  { user: principal }
  { notification-ids: (list 100 uint) }
)

;; Stores user preferences for which notification types they want to receive
(define-map user-preferences
  { user: principal }
  {
    mint-notifications: bool,
    price-change-notifications: bool,
    sale-notifications: bool,
    comment-notifications: bool,
    follow-notifications: bool,
    favorite-notifications: bool,
    followed-users-only: bool
  }
)

;; Tracks which users are following other users
(define-map user-follows
  { follower: principal, followee: principal }
  { timestamp: uint }
)

;; Counter to generate unique notification IDs
(define-data-var next-notification-id uint u1)

;; Private functions

;; Generates a new unique notification ID
(define-private (generate-notification-id)
  (let ((id (var-get next-notification-id)))
    (var-set next-notification-id (+ id u1))
    id
  )
)

;; Checks if an event type is valid
(define-private (is-valid-event-type (event-type uint))
  (or
    (is-eq event-type EVENT-TYPE-MINT)
    (is-eq event-type EVENT-TYPE-PRICE-CHANGE)
    (is-eq event-type EVENT-TYPE-SALE)
    (is-eq event-type EVENT-TYPE-COMMENT)
    (is-eq event-type EVENT-TYPE-FOLLOW)
    (is-eq event-type EVENT-TYPE-FAVORITE)
  )
)

;; Checks if a user wants to receive a specific type of notification
(define-private (should-notify (user principal) (event-type uint) (actor principal))
  (let (
    (preferences (default-to 
      ;; Default preferences if not set
      {
        mint-notifications: true,
        price-change-notifications: true,
        sale-notifications: true,
        comment-notifications: true,
        follow-notifications: true,
        favorite-notifications: true,
        followed-users-only: false
      }
      (map-get? user-preferences { user: user })
    ))
  )
    (and
      ;; Check if user wants this notification type
      (match event-type
        EVENT-TYPE-MINT (get mint-notifications preferences)
        EVENT-TYPE-PRICE-CHANGE (get price-change-notifications preferences)
        EVENT-TYPE-SALE (get sale-notifications preferences)
        EVENT-TYPE-COMMENT (get comment-notifications preferences)
        EVENT-TYPE-FOLLOW (get follow-notifications preferences)
        EVENT-TYPE-FAVORITE (get favorite-notifications preferences)
        false
      )
      ;; If followed-users-only is true, verify user follows the actor
      (if (get followed-users-only preferences)
        (is-some (map-get? user-follows { follower: user, followee: actor }))
        true
      )
    )
  )
)

;; Adds a notification ID to a user's notification list
(define-private (add-notification-to-user (user principal) (notification-id uint))
  (let (
    (current-notifications (default-to { notification-ids: (list) } 
                           (map-get? user-notifications { user: user })))
    (notification-ids (get notification-ids current-notifications))
  )
    ;; Insert the new notification ID at the beginning of the list
    (map-set user-notifications
      { user: user }
      { 
        notification-ids: (unwrap-panic 
          (as-max-len? (append notification-id notification-ids) u100)
        ) 
      }
    )
  )
)

;; Prunes the oldest notification if the user has reached the maximum number
(define-private (prune-old-notifications (user principal))
  (let (
    (current-notifications (default-to { notification-ids: (list) } 
                           (map-get? user-notifications { user: user })))
    (notification-ids (get notification-ids current-notifications))
  )
    (if (>= (len notification-ids) MAX-NOTIFICATIONS-PER-USER)
      ;; Remove oldest notification (last in list)
      (let (
        (oldest-id (unwrap-panic (element-at notification-ids (- (len notification-ids) u1))))
        (new-list (unwrap-panic (as-max-len? 
                    (slice notification-ids u0 (- (len notification-ids) u1))
                    u100)))
      )
        ;; Delete the notification data
        (map-delete notifications { notification-id: oldest-id })
        ;; Update the user's notification list
        (map-set user-notifications
          { user: user }
          { notification-ids: new-list }
        )
        (ok true)
      )
      (ok true)
    )
  )
)

;; Read-only functions

;; Get a specific notification by ID
(define-read-only (get-notification (notification-id uint))
  (map-get? notifications { notification-id: notification-id })
)

;; Get all notifications for a user
(define-read-only (get-user-notifications (user principal))
  (let (
    (user-notifs (default-to { notification-ids: (list) } 
                 (map-get? user-notifications { user: user })))
  )
    (ok (get notification-ids user-notifs))
  )
)

;; Get a user's notification preferences
(define-read-only (get-user-preferences (user principal))
  (default-to
    {
      mint-notifications: true,
      price-change-notifications: true,
      sale-notifications: true,
      comment-notifications: true,
      follow-notifications: true,
      favorite-notifications: true,
      followed-users-only: false
    }
    (map-get? user-preferences { user: user })
  )
)

;; Check if a user is following another user
(define-read-only (is-following (follower principal) (followee principal))
  (is-some (map-get? user-follows { follower: follower, followee: followee }))
)

;; Public functions

;; Create a new notification event
;; Only certain authorized contracts should be able to call this
(define-public (create-notification (event-type uint) 
                                   (target (optional principal)) 
                                   (resource-id (optional uint)) 
                                   (data (string-ascii 256)))
  (let (
    (sender tx-sender)
    (notification-id (generate-notification-id))
    (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
  )
    ;; Validate event type
    (asserts! (is-valid-event-type event-type) ERR-INVALID-EVENT-TYPE)
    
    ;; Create the notification record
    (map-set notifications
      { notification-id: notification-id }
      {
        event-type: event-type,
        actor: sender,
        target: target,
        resource-id: resource-id,
        timestamp: current-time,
        data: data,
        is-read: false
      }
    )
    
    ;; Add notification to the target user's list if applicable
    (match target
      target-principal
        (if (should-notify target-principal event-type sender)
          (begin
            (try! (prune-old-notifications target-principal))
            (add-notification-to-user target-principal notification-id)
          )
          true
        )
      true
    )
    
    (ok notification-id)
  )
)

;; Mark a notification as read
(define-public (mark-notification-read (notification-id uint))
  (let (
    (notification (map-get? notifications { notification-id: notification-id }))
  )
    ;; Ensure notification exists
    (asserts! (is-some notification) ERR-NOTIFICATION-NOT-FOUND)
    
    ;; Verify user is either the actor or target of the notification
    (asserts! 
      (or 
        (is-eq tx-sender (get actor (unwrap-panic notification)))
        (match (get target (unwrap-panic notification))
          target-principal (is-eq tx-sender target-principal)
          false
        )
      ) 
      ERR-NOT-AUTHORIZED
    )
    
    ;; Update notification to be marked as read
    (map-set notifications
      { notification-id: notification-id }
      (merge (unwrap-panic notification) { is-read: true })
    )
    
    (ok true)
  )
)

;; Mark all notifications for a user as read
(define-public (mark-all-notifications-read)
  (let (
    (user tx-sender)
    (user-notifs (default-to { notification-ids: (list) } 
                 (map-get? user-notifications { user: user })))
    (notification-ids (get notification-ids user-notifs))
  )
    ;; For each notification ID, mark it as read if the user is authorized
    (map 
      (lambda (notification-id)
        (let (
          (notification (map-get? notifications { notification-id: notification-id }))
        )
          (if (and
                (is-some notification)
                (or 
                  (is-eq user (get actor (unwrap-panic notification)))
                  (match (get target (unwrap-panic notification))
                    target-principal (is-eq user target-principal)
                    false
                  )
                )
              )
            (map-set notifications
              { notification-id: notification-id }
              (merge (unwrap-panic notification) { is-read: true })
            )
            true
          )
        )
      )
      notification-ids
    )
    
    (ok true)
  )
)

;; Update user notification preferences
(define-public (set-notification-preferences
  (mint-notifications bool)
  (price-change-notifications bool)
  (sale-notifications bool)
  (comment-notifications bool)
  (follow-notifications bool)
  (favorite-notifications bool)
  (followed-users-only bool)
)
  (map-set user-preferences
    { user: tx-sender }
    {
      mint-notifications: mint-notifications,
      price-change-notifications: price-change-notifications,
      sale-notifications: sale-notifications,
      comment-notifications: comment-notifications,
      follow-notifications: follow-notifications,
      favorite-notifications: favorite-notifications,
      followed-users-only: followed-users-only
    }
  )
  (ok true)
)

;; Follow a user
(define-public (follow-user (followee principal))
  (let (
    (follower tx-sender)
    (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
  )
    ;; Can't follow yourself
    (asserts! (not (is-eq follower followee)) ERR-NOT-AUTHORIZED)
    
    ;; Create follow relationship
    (map-set user-follows
      { follower: follower, followee: followee }
      { timestamp: current-time }
    )
    
    ;; Create a follow notification
    (create-notification 
      EVENT-TYPE-FOLLOW
      (some followee)
      none
      (concat (concat "User " (to-ascii follower)) " followed you")
    )
  )
)

;; Unfollow a user
(define-public (unfollow-user (followee principal))
  (let (
    (follower tx-sender)
  )
    ;; Delete the follow relationship
    (map-delete user-follows { follower: follower, followee: followee })
    
    (ok true)
  )
)

;; Delete a specific notification (only owner can delete)
(define-public (delete-notification (notification-id uint))
  (let (
    (notification (map-get? notifications { notification-id: notification-id }))
  )
    ;; Ensure notification exists
    (asserts! (is-some notification) ERR-NOTIFICATION-NOT-FOUND)
    
    ;; Verify user is authorized to delete
    (asserts! 
      (match (get target (unwrap-panic notification))
        target-principal (is-eq tx-sender target-principal)
        false
      ) 
      ERR-NOT-AUTHORIZED
    )
    
    ;; Delete the notification
    (map-delete notifications { notification-id: notification-id })
    
    ;; Also remove from user's notification list
    (let (
      (user-notifs (default-to { notification-ids: (list) } 
                   (map-get? user-notifications { user: tx-sender })))
      (notification-ids (get notification-ids user-notifs))
      (filtered-ids (filter (lambda (id) (not (is-eq id notification-id))) notification-ids))
    )
      (map-set user-notifications
        { user: tx-sender }
        { notification-ids: filtered-ids }
      )
    )
    
    (ok true)
  )
)