# 🌾 Produce Pre-Sale Platform

A decentralized platform connecting farmers with buyers through smart contracts for pre-sale of agricultural produce.

## 🎯 Features

- 👨‍🌾 Farmers can create produce listings with pricing and harvest dates
- 🛒 Buyers can purchase produce in advance
- 💫 Automatic payment processing and escrow
- ✅ Delivery confirmation system

## 📝 Contract Functions

### For Farmers

- `create-listing`: Create a new produce listing
  - Parameters: price-per-unit, total-units, harvest-date, produce-type
  - Returns: listing-id

- `confirm-delivery`: Confirm delivery of produce
  - Parameters: order-id
  - Returns: success status

### For Buyers

- `purchase-produce`: Purchase produce from a listing
  - Parameters: listing-id, units
  - Returns: order-id

### Read-Only Functions

- `get-listing`: Get details of a specific listing
- `get-order`: Get details of a specific order

## 🚀 Getting Started

1. Deploy the contract using Clarinet
2. Farmers can create listings for their upcoming harvests
3. Buyers can browse listings and make purchases
4. Upon harvest, farmers confirm delivery

## 💡 Example Usage

```clarity
;; Create a listing
(contract-call? .produce-pre-sale-platform create-listing u1000000 u100 u1677852800 "Organic Tomatoes")

;; Purchase produce
(contract-call? .produce-pre-sale-platform purchase-produce u1 u10)

;; Confirm delivery
(contract-call? .produce-pre-sale-platform confirm-delivery u1)
```
