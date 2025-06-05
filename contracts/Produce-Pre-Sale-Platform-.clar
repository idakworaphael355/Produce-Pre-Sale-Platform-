(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-LISTING-EXISTS (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-LISTING-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-PURCHASED (err u104))
(define-constant ERR-NOT-READY (err u105))

(define-data-var contract-owner principal tx-sender)

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
        delivery-status: (string-ascii 20)
    }
)

(define-data-var listing-nonce uint u0)
(define-data-var order-nonce uint u0)

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

(define-public (purchase-produce
    (listing-id uint)
    (units uint))
    (let
        ((listing (unwrap! (map-get? ProduceListing { listing-id: listing-id }) ERR-LISTING-NOT-FOUND))
         (total-cost (* units (get price-per-unit listing)))
         (order-id (+ (var-get order-nonce) u1)))
        
        (asserts! (<= units (get units-available listing)) ERR-INVALID-AMOUNT)
        (asserts! (is-eq (get status listing) "active") ERR-NOT-READY)
        
        (try! (stx-transfer? total-cost tx-sender (get farmer listing)))
        
        (map-set ProduceListing
            { listing-id: listing-id }
            (merge listing { 
                units-available: (- (get units-available listing) units)
            })
        )
        
        (map-set PurchaseOrders
            { order-id: order-id }
            {
                buyer: tx-sender,
                listing-id: listing-id,
                units-purchased: units,
                total-price: total-cost,
                delivery-status: "pending"
            }
        )
        
        (var-set order-nonce order-id)
        (ok order-id)
    )
)

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

(define-read-only (get-listing
    (listing-id uint))
    (ok (map-get? ProduceListing { listing-id: listing-id }))
)

(define-read-only (get-order
    (order-id uint))
    (ok (map-get? PurchaseOrders { order-id: order-id }))
)
