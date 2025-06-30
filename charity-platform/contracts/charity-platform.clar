;; NFT-based charity platform smart contract
;; This contract allows users to mint NFTs, donate to charities, and participate in charitable campaigns

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-listing-expired (err u102))
(define-constant err-invalid-price (err u103))
(define-constant err-campaign-not-found (err u104))
(define-constant err-campaign-expired (err u105))
(define-constant err-insufficient-funds (err u106))
(define-constant err-invalid-parameter (err u107))

;; Data variables
(define-data-var total-nfts uint u0)
(define-data-var charity-address principal 'SP000000000000000000002Q6VF78)
(define-data-var donation-percentage uint u20)
(define-data-var total-donations uint u0)
(define-data-var paused bool false)

;; NFT data maps
(define-map nft-owners uint principal)
(define-map token-uri uint (string-utf8 256))
(define-map nft-price uint uint)
(define-map nft-metadata 
    uint 
    {creator: principal, 
     timestamp: uint, 
     category: (string-utf8 64)}
)

;; Charity campaign data
(define-map charity-campaigns 
    uint 
    {name: (string-utf8 64),
     description: (string-utf8 256),
     goal: uint,
     raised: uint,
     deadline: uint,
     active: bool}
)

(define-data-var campaign-counter uint u0)

;; Donation history
(define-map user-donations 
    {user: principal, campaign-id: uint} 
    {amount: uint, timestamp: uint}
)


;; Read-only functions
(define-read-only (get-token-uri (token-id uint))
    (map-get? token-uri token-id)
)

(define-read-only (get-owner (token-id uint))
    (map-get? nft-owners token-id)
)

(define-read-only (get-price (token-id uint))
    (map-get? nft-price token-id)
)

(define-read-only (get-token-metadata (token-id uint))
    (map-get? nft-metadata token-id)
)

(define-read-only (get-campaign-details (campaign-id uint))
    (map-get? charity-campaigns campaign-id)
)

(define-read-only (get-user-donation-history (user principal) (campaign-id uint))
    (map-get? user-donations {user: user, campaign-id: campaign-id})
)


;; Private functions
(define-private (check-owner (token-id uint) (acc uint))
    (if (is-eq (some tx-sender) (map-get? nft-owners token-id))
        (+ acc u1)
        acc
    )
)

(define-private (transfer-token (token-id uint) (sender principal) (recipient principal))
    (begin
        (map-set nft-owners token-id recipient)
        (ok true)
    )
)

;; Public functions - NFT Core
(define-public (mint (uri (string-utf8 256)) (category (string-utf8 64)))
    (let ((token-id (+ (var-get total-nfts) u1)))
        (begin
            (asserts! (not (var-get paused)) (err u108))
            (map-set nft-owners token-id tx-sender)
            (map-set token-uri token-id uri)
            (map-set nft-metadata token-id 
                {creator: tx-sender,
                 timestamp: block-height,
                 category: category})
            (var-set total-nfts token-id)
            (ok token-id)
        )
    )
)

;; Public functions - NFT Trading
(define-public (transfer (token-id uint) (recipient principal))
    (let ((owner (unwrap! (map-get? nft-owners token-id) (err u1))))
        (asserts! (is-eq tx-sender owner) err-not-token-owner)
        (transfer-token token-id owner recipient)
    )
)

(define-public (list-for-sale (token-id uint) (price uint))
    (let ((owner (unwrap! (map-get? nft-owners token-id) (err u1))))
        (begin
            (asserts! (not (var-get paused)) (err u108))
            (asserts! (is-eq tx-sender owner) err-not-token-owner)
            (asserts! (> price u0) err-invalid-price)
            (map-set nft-price token-id price)
            (ok true)
        )
    )
)

;; Public functions - Charity Campaigns
(define-public (create-charity-campaign 
    (name (string-utf8 64))
    (description (string-utf8 256))
    (goal uint)
    (duration uint))
    (let ((campaign-id (+ (var-get campaign-counter) u1)))
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (asserts! (> goal u0) err-invalid-parameter)
            (map-set charity-campaigns campaign-id
                {name: name,
                 description: description,
                 goal: goal,
                 raised: u0,
                 deadline: (+ block-height duration),
                 active: true})
            (var-set campaign-counter campaign-id)
            (ok campaign-id)
        )
    )
)

(define-public (donate-to-campaign (campaign-id uint) (amount uint))
    (let ((campaign (unwrap! (map-get? charity-campaigns campaign-id) err-campaign-not-found)))
        (begin
            (asserts! (get active campaign) err-campaign-not-found)
            (asserts! (<= block-height (get deadline campaign)) err-campaign-expired)
            (try! (stx-transfer? amount tx-sender (var-get charity-address)))
            (map-set charity-campaigns campaign-id
                (merge campaign {raised: (+ (get raised campaign) amount)}))
            (map-set user-donations 
                {user: tx-sender, campaign-id: campaign-id}
                {amount: amount, timestamp: block-height})
            (var-set total-donations (+ (var-get total-donations) amount))
            (ok true)
        )
    )
)

;; Public functions - Marketplace with Charity
(define-public (buy-nft (token-id uint))
    (let 
        (
            (price (unwrap! (map-get? nft-price token-id) err-invalid-price))
            (owner (unwrap! (map-get? nft-owners token-id) err-not-token-owner))
            (donation-amount (/ (* price (var-get donation-percentage)) u100))
            (seller-amount (- price donation-amount))
        )
        (begin
            (asserts! (not (var-get paused)) err-invalid-price)
            (asserts! (>= (stx-get-balance tx-sender) price) err-insufficient-funds)
            
            ;; Transfer payment to seller
            (unwrap! (stx-transfer? seller-amount tx-sender owner) err-insufficient-funds)
            
            ;; Transfer donation to charity
            (unwrap! (stx-transfer? donation-amount tx-sender (var-get charity-address)) err-insufficient-funds)
            
            ;; Transfer NFT ownership
            (unwrap! (transfer-token token-id owner tx-sender) err-not-token-owner)
            
            ;; Cleanup and update state
            (map-delete nft-price token-id)
            (var-set total-donations (+ (var-get total-donations) donation-amount))
            (ok true)
        )
    )
)

;; Administrative functions
(define-public (set-charity-address (new-address principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set charity-address new-address)
        (ok true)
    )
)

(define-public (set-donation-percentage (new-percentage uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-percentage u100) (err u104))
        (var-set donation-percentage new-percentage)
        (ok true)
    )
)

(define-public (toggle-pause)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set paused (not (var-get paused)))
        (ok true)
    )
)

(define-public (end-campaign (campaign-id uint))
    (let ((campaign (unwrap! (map-get? charity-campaigns campaign-id) err-campaign-not-found)))
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (map-set charity-campaigns campaign-id
                (merge campaign {active: false}))
            (ok true)
        )
    )
)

