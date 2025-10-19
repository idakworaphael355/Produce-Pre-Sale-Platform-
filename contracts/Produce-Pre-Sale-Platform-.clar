;; Produce Pre-Sale Platform Smart Contract with Inventory Tracking
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
(define-constant ERR-INSUFFICIENT-POINTS (err u114))
(define-constant ERR-INVALID-DISCOUNT (err u115))
(define-constant ERR-INVENTORY-NOT-FOUND (err u116))
(define-constant ERR-INSUFFICIENT-STOCK (err u117))
(define-constant ERR-INVALID-QUANTITY (err u118))
(define-constant ERR-EXPIRED-PRODUCE (err u119))
(define-constant ERR-LOW-STOCK-THRESHOLD (err u120))

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

(define-map LoyaltyPoints
    { buyer: principal }
    {
        total-points: uint,
        points-used: uint,
        current-balance: uint,
        last-updated: uint
    }
)

(define-map PointRedemptions
    { redemption-id: uint }
    {
        buyer: principal,
        points-redeemed: uint,
        discount-amount: uint,
        order-id: uint,
        timestamp: uint
    }
)

;; Inventory tracking data maps
(define-map FarmInventory
    { farmer: principal, produce-type: (string-ascii 64) }
    {
        current-stock: uint,
        reserved-stock: uint,
        available-stock: uint,
        total-harvested: uint,
        expiry-date: uint,
        reorder-threshold: uint,
        last-updated: uint,
        location: (string-ascii 100)
    }
)

(define-map InventoryMovements
    { movement-id: uint }
    {
        farmer: principal,
        produce-type: (string-ascii 64),
        movement-type: (string-ascii 20),
        quantity: uint,
        reason: (string-ascii 100),
        timestamp: uint,
        batch-id: (string-ascii 50)
    }
)

(define-map StockAlerts
    { alert-id: uint }
    {
        farmer: principal,
        produce-type: (string-ascii 64),
        alert-type: (string-ascii 30),
        current-stock: uint,
        threshold: uint,
        status: (string-ascii 20),
        created-at: uint
    }
)

;; Data variables for nonces
(define-data-var listing-nonce uint u0)
(define-data-var order-nonce uint u0)
(define-data-var proposal-nonce uint u0)
(define-data-var redemption-nonce uint u0)
(define-data-var movement-nonce uint u0)
(define-data-var alert-nonce uint u0)

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
        
        ;; Award loyalty points to buyer (1 point per STX spent)
        (unwrap-panic (award-loyalty-points tx-sender total-cost))
        
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

;; Award loyalty points
(define-private (award-loyalty-points
    (buyer principal)
    (amount uint))
    (let
        ((current-loyalty (default-to 
            { total-points: u0, points-used: u0, current-balance: u0, last-updated: u0 }
            (map-get? LoyaltyPoints { buyer: buyer })))
         (points-to-award amount)
         (new-total-points (+ (get total-points current-loyalty) points-to-award))
         (new-current-balance (+ (get current-balance current-loyalty) points-to-award)))
        
        (map-set LoyaltyPoints
            { buyer: buyer }
            {
                total-points: new-total-points,
                points-used: (get points-used current-loyalty),
                current-balance: new-current-balance,
                last-updated: stacks-block-height
            }
        )
        (ok true)
    )
)

;; ============================================
;; INVENTORY TRACKING FUNCTIONS
;; ============================================

;; Initialize inventory for a produce type
(define-public (initialize-inventory
    (produce-type (string-ascii 64))
    (initial-stock uint)
    (expiry-date uint)
    (reorder-threshold uint)
    (location (string-ascii 100)))
    (let
        ((inventory-key { farmer: tx-sender, produce-type: produce-type })
         (movement-id (+ (var-get movement-nonce) u1)))
        
        (asserts! (is-none (map-get? FarmInventory inventory-key)) ERR-LISTING-EXISTS)
        (asserts! (> initial-stock u0) ERR-INVALID-QUANTITY)
        (asserts! (> expiry-date stacks-block-height) ERR-EXPIRED-PRODUCE)
        
        ;; Create inventory entry
        (map-set FarmInventory
            inventory-key
            {
                current-stock: initial-stock,
                reserved-stock: u0,
                available-stock: initial-stock,
                total-harvested: initial-stock,
                expiry-date: expiry-date,
                reorder-threshold: reorder-threshold,
                last-updated: stacks-block-height,
                location: location
            }
        )
        
        ;; Record initial stock movement
        (map-set InventoryMovements
            { movement-id: movement-id }
            {
                farmer: tx-sender,
                produce-type: produce-type,
                movement-type: "harvest",
                quantity: initial-stock,
                reason: "Initial stock",
                timestamp: stacks-block-height,
                batch-id: ""
            }
        )
        
        (var-set movement-nonce movement-id)
        (ok true)
    )
)

;; Update stock levels (harvest or spoilage)
(define-public (update-stock
    (produce-type (string-ascii 64))
    (quantity uint)
    (movement-type (string-ascii 20))
    (reason (string-ascii 100))
    (batch-id (string-ascii 50)))
    (let
        ((inventory-key { farmer: tx-sender, produce-type: produce-type })
         (inventory (unwrap! (map-get? FarmInventory inventory-key) ERR-INVENTORY-NOT-FOUND))
         (movement-id (+ (var-get movement-nonce) u1)))
        
        (asserts! (> quantity u0) ERR-INVALID-QUANTITY)
        
        ;; Calculate new stock levels based on movement type
        (let
            ((new-current-stock 
                (if (is-eq movement-type "harvest")
                    (+ (get current-stock inventory) quantity)
                    (if (or (is-eq movement-type "spoilage") (is-eq movement-type "sold"))
                        (begin
                            (asserts! (>= (get current-stock inventory) quantity) ERR-INSUFFICIENT-STOCK)
                            (- (get current-stock inventory) quantity)
                        )
                        (get current-stock inventory)
                    )
                ))
             (new-available-stock (- new-current-stock (get reserved-stock inventory)))
             (new-total-harvested 
                (if (is-eq movement-type "harvest")
                    (+ (get total-harvested inventory) quantity)
                    (get total-harvested inventory)
                )))
            
            ;; Update inventory
            (map-set FarmInventory
                inventory-key
                (merge inventory {
                    current-stock: new-current-stock,
                    available-stock: new-available-stock,
                    total-harvested: new-total-harvested,
                    last-updated: stacks-block-height
                })
            )
            
            ;; Record movement
            (map-set InventoryMovements
                { movement-id: movement-id }
                {
                    farmer: tx-sender,
                    produce-type: produce-type,
                    movement-type: movement-type,
                    quantity: quantity,
                    reason: reason,
                    timestamp: stacks-block-height,
                    batch-id: batch-id
                }
            )
            
            ;; Check for low stock and create alert if needed
            (if (< new-current-stock (get reorder-threshold inventory))
                (unwrap-panic (create-stock-alert produce-type "low-stock" new-current-stock (get reorder-threshold inventory)))
                u0
            )
            
            (var-set movement-nonce movement-id)
            (ok new-current-stock)
        )
    )
)

;; Reserve stock for orders
(define-public (reserve-stock
    (produce-type (string-ascii 64))
    (quantity uint))
    (let
        ((inventory-key { farmer: tx-sender, produce-type: produce-type })
         (inventory (unwrap! (map-get? FarmInventory inventory-key) ERR-INVENTORY-NOT-FOUND)))
        
        (asserts! (> quantity u0) ERR-INVALID-QUANTITY)
        (asserts! (>= (get available-stock inventory) quantity) ERR-INSUFFICIENT-STOCK)
        
        (let
            ((new-reserved-stock (+ (get reserved-stock inventory) quantity))
             (new-available-stock (- (get available-stock inventory) quantity)))
            
            (map-set FarmInventory
                inventory-key
                (merge inventory {
                    reserved-stock: new-reserved-stock,
                    available-stock: new-available-stock,
                    last-updated: stacks-block-height
                })
            )
            
            (ok true)
        )
    )
)

;; Release reserved stock
(define-public (release-reserved-stock
    (produce-type (string-ascii 64))
    (quantity uint))
    (let
        ((inventory-key { farmer: tx-sender, produce-type: produce-type })
         (inventory (unwrap! (map-get? FarmInventory inventory-key) ERR-INVENTORY-NOT-FOUND)))
        
        (asserts! (> quantity u0) ERR-INVALID-QUANTITY)
        (asserts! (>= (get reserved-stock inventory) quantity) ERR-INSUFFICIENT-STOCK)
        
        (let
            ((new-reserved-stock (- (get reserved-stock inventory) quantity))
             (new-available-stock (+ (get available-stock inventory) quantity)))
            
            (map-set FarmInventory
                inventory-key
                (merge inventory {
                    reserved-stock: new-reserved-stock,
                    available-stock: new-available-stock,
                    last-updated: stacks-block-height
                })
            )
            
            (ok true)
        )
    )
)

;; Create stock alert
(define-private (create-stock-alert
    (produce-type (string-ascii 64))
    (alert-type (string-ascii 30))
    (current-stock uint)
    (threshold uint))
    (let
        ((alert-id (+ (var-get alert-nonce) u1)))
        
        (map-set StockAlerts
            { alert-id: alert-id }
            {
                farmer: tx-sender,
                produce-type: produce-type,
                alert-type: alert-type,
                current-stock: current-stock,
                threshold: threshold,
                status: "active",
                created-at: stacks-block-height
            }
        )
        
        (var-set alert-nonce alert-id)
        (ok alert-id)
    )
)

;; Mark alert as resolved
(define-public (resolve-stock-alert
    (alert-id uint))
    (let
        ((alert (unwrap! (map-get? StockAlerts { alert-id: alert-id }) ERR-LISTING-NOT-FOUND)))
        
        (asserts! (is-eq tx-sender (get farmer alert)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status alert) "active") ERR-ALREADY-PURCHASED)
        
        (map-set StockAlerts
            { alert-id: alert-id }
            (merge alert { status: "resolved" })
        )
        
        (ok true)
    )
)

;; Batch update multiple produce types
(define-public (batch-update-stock
    (updates (list 5 { produce-type: (string-ascii 64), quantity: uint, movement-type: (string-ascii 20), reason: (string-ascii 100) })))
    (let
        ((results (map process-single-update updates)))
        (ok results)
    )
)

;; Process single update in batch
(define-private (process-single-update
    (update { produce-type: (string-ascii 64), quantity: uint, movement-type: (string-ascii 20), reason: (string-ascii 100) }))
    (update-stock 
        (get produce-type update)
        (get quantity update)
        (get movement-type update)
        (get reason update)
        ""
    )
)

;; Read-only functions for core contract
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

(define-read-only (get-farmer-reputation
    (farmer principal))
    (ok (map-get? FarmerReputation { farmer: farmer }))
)

;; Read-only functions for inventory tracking
(define-read-only (get-inventory
    (farmer principal)
    (produce-type (string-ascii 64)))
    (ok (map-get? FarmInventory { farmer: farmer, produce-type: produce-type }))
)

(define-read-only (get-inventory-movement
    (movement-id uint))
    (ok (map-get? InventoryMovements { movement-id: movement-id }))
)

(define-read-only (get-stock-alert
    (alert-id uint))
    (ok (map-get? StockAlerts { alert-id: alert-id }))
)

;; Check if produce is expired
(define-read-only (is-produce-expired
    (farmer principal)
    (produce-type (string-ascii 64)))
    (let
        ((inventory (map-get? FarmInventory { farmer: farmer, produce-type: produce-type })))
        (match inventory
            inv (ok (some (> stacks-block-height (get expiry-date inv))))
            (ok none)
        )
    )
)

;; Get total value of inventory
(define-read-only (calculate-inventory-value
    (farmer principal)
    (produce-type (string-ascii 64))
    (price-per-unit uint))
    (let
        ((inventory (map-get? FarmInventory { farmer: farmer, produce-type: produce-type })))
        (match inventory
            inv (ok (* (get current-stock inv) price-per-unit))
            (ok u0)
        )
    )
)

(define-read-only (get-contract-owner)
    (ok (var-get contract-owner))
)
