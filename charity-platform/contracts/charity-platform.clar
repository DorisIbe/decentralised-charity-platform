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

