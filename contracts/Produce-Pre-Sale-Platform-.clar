;; Produce Pre-Sale Platform Smart Contract
;; Constants for error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-LISTING-EXISTS (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-LISTING-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-PURCHASED (err u104))
(define-constant ERR-NOT-READY (err u105))
(define-constant ERR-DISPUTE-EXISTS (err u106))
(define-constant ERR-NO-DISPUTE (err u107))
(define-constant ERR-DISPUTE-RESOLVED (err u108))
(define-constant ERR-ALREADY-REVIEWED (err u109))
(define-constant ERR-INVALID-RATING (err u110))
(define-constant ERR-PROPOSAL-EXISTS (err u111))
(define-constant ERR-INVALID-PRICE (err u112))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u113))

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Data maps
(define-map ProduceListing
    { listing-id: uint }
    {
        farmer: principal,
        price-per-unit: uint,
        total-units: uint,
        units-available: uint,
        harvest-date: uint,
        produce-type: (string-ascii 64),
        status: (string-ascii 20)
    }
)

(define-map PurchaseOrders
    { order-id: uint }
    {
        buyer: principal,
        listing-id: uint,
        units-purchased: uint,
        total-price: uint,
        delivery-status: (string-ascii 20),
        escrow-status: (string-ascii 20),
        reviewed: bool
    }
)

(define-map EscrowFunds
    { order-id: uint }
    {
        amount: uint,
        released: bool
    }
)

(define-map Disputes
    { order-id: uint }
    {
        initiated-by: principal,
        reason: (string-ascii 256),
        status: (string-ascii 20),
        resolution: (string-ascii 20)
    }
)

(define-map FarmerReputation
    { farmer: principal }
    {
        total-rating: uint,
        review-count: uint,
        average-rating: uint,
        total-sales: uint
    }
)

(define-map Reviews
    { order-id: uint }
    {
        reviewer: principal,
        farmer: principal,
        rating: uint,
        review-text: (string-ascii 500),
        timestamp: uint
    }
)

(define-map MarketDemand
    { produce-type: (string-ascii 64) }
    {
        total-inquiries: uint,
        average-proposed-price: uint,
        last-updated: uint
    }
)

(define-map PriceProposals
    { proposal-id: uint }
    {
        buyer: principal,
        produce-type: (string-ascii 64),
        proposed-price: uint,
        units-wanted: uint,
        timestamp: uint,
        status: (string-ascii 20)
    }
)

;; Data variables for nonces
(define-data-var listing-nonce uint u0)
(define-data-var order-nonce uint u0)
(define-data-var proposal-nonce uint u0)

;; Create a new produce listing
(define-public (create-listing 
    (price-per-unit uint)
    (total-units uint)
    (harvest-date uint)
    (produce-type (string-ascii 64)))
    (let
        ((listing-id (+ (var-get listing-nonce) u1)))
        (map-set ProduceListing
            { listing-id: listing-id }
            {
                farmer: tx-sender,
                price-per-unit: price-per-unit,
                total-units: total-units,
                units-available: total-units,
                harvest-date: harvest-date,
                produce-type: produce-type,
                status: "active"
            }
        )
        (var-set listing-nonce listing-id)
        (ok listing-id)
    )
)

;; Purchase produce with escrow
(define-public (purchase-produce
    (listing-id uint)
    (units uint))
    (let
        ((listing (unwrap! (map-get? ProduceListing { listing-id: listing-id }) ERR-LISTING-NOT-FOUND))
         (total-cost (* units (get price-per-unit listing)))
         (order-id (+ (var-get order-nonce) u1)))
        
        (asserts! (<= units (get units-available listing)) ERR-INVALID-AMOUNT)
        (asserts! (is-eq (get status listing) "active") ERR-NOT-READY)
        
        ;; Transfer funds to contract for escrow
        (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
        
        ;; Update listing availability
        (map-set ProduceListing
            { listing-id: listing-id }
            (merge listing { 
                units-available: (- (get units-available listing) units)
            })
        )
        
        ;; Create purchase order
        (map-set PurchaseOrders
            { order-id: order-id }
            {
                buyer: tx-sender,
                listing-id: listing-id,
                units-purchased: units,
                total-price: total-cost,
                delivery-status: "pending",
                escrow-status: "held",
                reviewed: false
            }
        )
        
        ;; Create escrow entry
        (map-set EscrowFunds
            { order-id: order-id }
            {
                amount: total-cost,
                released: false
            }
        )
        
        ;; Update farmer sales count
        (unwrap-panic (update-farmer-sales (get farmer listing)))
        
        (var-set order-nonce order-id)
        (ok order-id)
    )
)

;; Confirm delivery (farmer only)
(define-public (confirm-delivery
    (order-id uint))
    (let
        ((order (unwrap! (map-get? PurchaseOrders { order-id: order-id }) ERR-LISTING-NOT-FOUND))
         (listing (unwrap! (map-get? ProduceListing { listing-id: (get listing-id order) }) ERR-LISTING-NOT-FOUND)))
        
        (asserts! (is-eq tx-sender (get farmer listing)) ERR-NOT-AUTHORIZED)
        
        (map-set PurchaseOrders
            { order-id: order-id }
            (merge order {
                delivery-status: "delivered"
            })
        )
        (ok true)
    )
)

;; Release escrow funds (buyer only)
(define-public (release-escrow
    (order-id uint))
    (let
        ((order (unwrap! (map-get? PurchaseOrders { order-id: order-id }) ERR-LISTING-NOT-FOUND))
         (listing (unwrap! (map-get? ProduceListing { listing-id: (get listing-id order) }) ERR-LISTING-NOT-FOUND))
         (escrow (unwrap! (map-get? EscrowFunds { order-id: order-id }) ERR-LISTING-NOT-FOUND)))
        
        (asserts! (is-eq tx-sender (get buyer order)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get delivery-status order) "delivered") ERR-NOT-READY)
        (asserts! (is-eq (get released escrow) false) ERR-ALREADY-PURCHASED)
        
        ;; Release funds to farmer
        (try! (as-contract (stx-transfer? (get amount escrow) tx-sender (get farmer listing))))
        
        ;; Update escrow status
        (map-set EscrowFunds
            { order-id: order-id }
            (merge escrow { released: true })
        )
        
        (map-set PurchaseOrders
            { order-id: order-id }
            (merge order { escrow-status: "released" })
        )
        
        (ok true)
    )
)

;; Initiate dispute
(define-public (initiate-dispute
    (order-id uint)
    (reason (string-ascii 256)))
    (let
        ((order (unwrap! (map-get? PurchaseOrders { order-id: order-id }) ERR-LISTING-NOT-FOUND))
         (listing (unwrap! (map-get? ProduceListing { listing-id: (get listing-id order) }) ERR-LISTING-NOT-FOUND)))
        
        (asserts! (or (is-eq tx-sender (get buyer order)) (is-eq tx-sender (get farmer listing))) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (map-get? Disputes { order-id: order-id })) ERR-DISPUTE-EXISTS)
        
        (map-set Disputes
            { order-id: order-id }
            {
                initiated-by: tx-sender,
                reason: reason,
                status: "open",
                resolution: "pending"
            }
        )
        
        (ok true)
    )
)

;; Resolve dispute (contract owner only)
(define-public (resolve-dispute
    (order-id uint)
    (resolution (string-ascii 20)))
    (let
        ((dispute (unwrap! (map-get? Disputes { order-id: order-id }) ERR-NO-DISPUTE))
         (order (unwrap! (map-get? PurchaseOrders { order-id: order-id }) ERR-LISTING-NOT-FOUND))
         (listing (unwrap! (map-get? ProduceListing { listing-id: (get listing-id order) }) ERR-LISTING-NOT-FOUND))
         (escrow (unwrap! (map-get? EscrowFunds { order-id: order-id }) ERR-LISTING-NOT-FOUND)))
        
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status dispute) "open") ERR-DISPUTE-RESOLVED)
        
        ;; Release funds based on resolution
        (if (is-eq resolution "buyer")
            (try! (as-contract (stx-transfer? (get amount escrow) tx-sender (get buyer order))))
            (try! (as-contract (stx-transfer? (get amount escrow) tx-sender (get farmer listing))))
        )
        
        ;; Update dispute status
        (map-set Disputes
            { order-id: order-id }
            (merge dispute {
                status: "resolved",
                resolution: resolution
            })
        )
        
        ;; Update escrow status
        (map-set EscrowFunds
            { order-id: order-id }
            (merge escrow { released: true })
        )
        
        (map-set PurchaseOrders
            { order-id: order-id }
            (merge order { escrow-status: "resolved" })
        )
        
        (ok true)
    )
)

;; Submit review (buyer only)
(define-public (submit-review
    (order-id uint)
    (rating uint)
    (review-text (string-ascii 500)))
    (let
        ((order (unwrap! (map-get? PurchaseOrders { order-id: order-id }) ERR-LISTING-NOT-FOUND))
         (listing (unwrap! (map-get? ProduceListing { listing-id: (get listing-id order) }) ERR-LISTING-NOT-FOUND)))
        
        (asserts! (is-eq tx-sender (get buyer order)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get delivery-status order) "delivered") ERR-NOT-READY)
        (asserts! (is-eq (get reviewed order) false) ERR-ALREADY-REVIEWED)
        (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
        
        ;; Create review entry
        (map-set Reviews
            { order-id: order-id }
            {
                reviewer: tx-sender,
                farmer: (get farmer listing),
                rating: rating,
                review-text: review-text,
                timestamp: stacks-block-height
            }
        )
        
        ;; Mark order as reviewed
        (map-set PurchaseOrders
            { order-id: order-id }
            (merge order { reviewed: true })
        )
        
        ;; Update farmer reputation
        (unwrap-panic (update-farmer-reputation (get farmer listing) rating))
        
        (ok true)
    )
)

;; Update farmer sales count
(define-private (update-farmer-sales
    (farmer principal))
    (let
        ((reputation (default-to 
            { total-rating: u0, review-count: u0, average-rating: u0, total-sales: u0 }
            (map-get? FarmerReputation { farmer: farmer }))))
        
        (begin
            (map-set FarmerReputation
                { farmer: farmer }
                (merge reputation { total-sales: (+ (get total-sales reputation) u1) })
            )
            (ok true)
        )
    )
)

;; Update farmer reputation
(define-private (update-farmer-reputation
    (farmer principal)
    (rating uint))
    (let
        ((reputation (default-to 
            { total-rating: u0, review-count: u0, average-rating: u0, total-sales: u0 }
            (map-get? FarmerReputation { farmer: farmer })))
         (new-total-rating (+ (get total-rating reputation) rating))
         (new-review-count (+ (get review-count reputation) u1))
         (new-average-rating (/ new-total-rating new-review-count)))
        
        (map-set FarmerReputation
            { farmer: farmer }
            (merge reputation {
                total-rating: new-total-rating,
                review-count: new-review-count,
                average-rating: new-average-rating
            })
        )
        (ok true)
    )
)

;; Submit price proposal
(define-public (submit-price-proposal
    (produce-type (string-ascii 64))
    (proposed-price uint)
    (units-wanted uint))
    (let
        ((proposal-id (+ (var-get proposal-nonce) u1))
         (current-demand (default-to 
            { total-inquiries: u0, average-proposed-price: u0, last-updated: u0 }
            (map-get? MarketDemand { produce-type: produce-type }))))
        
        (asserts! (> proposed-price u0) ERR-INVALID-PRICE)
        (asserts! (> units-wanted u0) ERR-INVALID-AMOUNT)
        
        (map-set PriceProposals
            { proposal-id: proposal-id }
            {
                buyer: tx-sender,
                produce-type: produce-type,
                proposed-price: proposed-price,
                units-wanted: units-wanted,
                timestamp: stacks-block-height,
                status: "active"
            }
        )
        
        (let
            ((new-total-inquiries (+ (get total-inquiries current-demand) u1))
             (current-total-value (* (get total-inquiries current-demand) (get average-proposed-price current-demand)))
             (new-total-value (+ current-total-value proposed-price))
             (new-average-price (if (> new-total-inquiries u0)
                                   (/ new-total-value new-total-inquiries)
                                   u0)))
            
            (map-set MarketDemand
                { produce-type: produce-type }
                {
                    total-inquiries: new-total-inquiries,
                    average-proposed-price: new-average-price,
                    last-updated: stacks-block-height
                }
            )
        )
        
        (var-set proposal-nonce proposal-id)
        (ok proposal-id)
    )
)

;; Accept price proposal (farmer only)
(define-public (accept-price-proposal
    (proposal-id uint))
    (let
        ((proposal (unwrap! (map-get? PriceProposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND)))
        
        (asserts! (is-eq (get status proposal) "active") ERR-PROPOSAL-NOT-FOUND)
        
        (map-set PriceProposals
            { proposal-id: proposal-id }
            (merge proposal { status: "accepted" })
        )
        
        (ok true)
    )
)

;; Get market insights for produce type
(define-read-only (get-market-demand
    (produce-type (string-ascii 64)))
    (ok (map-get? MarketDemand { produce-type: produce-type }))
)

;; Get suggested price based on market demand
(define-read-only (get-suggested-price
    (produce-type (string-ascii 64)))
    (let
        ((demand-data (map-get? MarketDemand { produce-type: produce-type })))
        (match demand-data
            market-info
                (let
                    ((base-price (get average-proposed-price market-info))
                     (demand-factor (if (> (get total-inquiries market-info) u5)
                                      (/ (get total-inquiries market-info) u5)
                                      u1))
                     (suggested-price (+ base-price (/ (* base-price demand-factor) u10))))
                    (ok (some suggested-price))
                )
            (ok none)
        )
    )
)

;; Read-only functions
(define-read-only (get-listing
    (listing-id uint))
    (ok (map-get? ProduceListing { listing-id: listing-id }))
)

(define-read-only (get-order
    (order-id uint))
    (ok (map-get? PurchaseOrders { order-id: order-id }))
)

(define-read-only (get-escrow
    (order-id uint))
    (ok (map-get? EscrowFunds { order-id: order-id }))
)

(define-read-only (get-dispute
    (order-id uint))
    (ok (map-get? Disputes { order-id: order-id }))
)

(define-read-only (get-farmer-reputation
    (farmer principal))
    (ok (map-get? FarmerReputation { farmer: farmer }))
)

(define-read-only (get-review
    (order-id uint))
    (ok (map-get? Reviews { order-id: order-id }))
)

(define-read-only (get-price-proposal
    (proposal-id uint))
    (ok (map-get? PriceProposals { proposal-id: proposal-id }))
)

(define-read-only (get-contract-owner)
    (ok (var-get contract-owner))
)
