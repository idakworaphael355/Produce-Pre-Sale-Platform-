import {
  Cl,
  ClarityType,
  cvToJSON,
  cvToString,
} from "@stacks/transactions";
import { describe, expect, it, beforeEach } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const farmer1 = accounts.get("wallet_1")!;
const farmer2 = accounts.get("wallet_2")!;
const buyer1 = accounts.get("wallet_3")!;
const buyer2 = accounts.get("wallet_4")!;

describe("Produce Pre-Sale Platform - Inventory Tracking", () => {
  beforeEach(() => {
    simnet.setEpoch('3.1');
  });

  describe("Core Listing Functions", () => {
    it("should create a produce listing successfully", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "create-listing",
        [
          Cl.uint(1000000), // price-per-unit: 1 STX
          Cl.uint(100),     // total-units
          Cl.uint(1000),    // harvest-date
          Cl.stringAscii("Organic Tomatoes")
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.uint(1));
    });

    it("should purchase produce and create escrow", () => {
      // First create a listing
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "create-listing",
        [
          Cl.uint(1000000),
          Cl.uint(100),
          Cl.uint(1000),
          Cl.stringAscii("Organic Tomatoes")
        ],
        farmer1
      );

      // Purchase produce
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "purchase-produce",
        [
          Cl.uint(1), // listing-id
          Cl.uint(10) // units
        ],
        buyer1
      );

      expect(result).toBeOk(Cl.uint(1));
    });
  });

  describe("Inventory Management", () => {
    it("should initialize inventory successfully", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Organic Tomatoes"),
          Cl.uint(500),      // initial-stock
          Cl.uint(2000),     // expiry-date
          Cl.uint(50),       // reorder-threshold
          Cl.stringAscii("Farm A - Warehouse 1")
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to initialize duplicate inventory", () => {
      // Initialize first time
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Organic Tomatoes"),
          Cl.uint(500),
          Cl.uint(2000),
          Cl.uint(50),
          Cl.stringAscii("Farm A")
        ],
        farmer1
      );

      // Try to initialize again
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Organic Tomatoes"),
          Cl.uint(300),
          Cl.uint(1800),
          Cl.uint(30),
          Cl.stringAscii("Farm A")
        ],
        farmer1
      );

      expect(result).toBeErr(Cl.uint(101)); // ERR-LISTING-EXISTS
    });

    it("should fail with expired produce", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Expired Tomatoes"),
          Cl.uint(100),
          Cl.uint(0), // expired date
          Cl.uint(10),
          Cl.stringAscii("Farm A")
        ],
        farmer1
      );

      expect(result).toBeErr(Cl.uint(119)); // ERR-EXPIRED-PRODUCE
    });

    it("should fail with zero initial stock", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Zero Stock"),
          Cl.uint(0), // zero stock
          Cl.uint(2000),
          Cl.uint(10),
          Cl.stringAscii("Farm A")
        ],
        farmer1
      );

      expect(result).toBeErr(Cl.uint(118)); // ERR-INVALID-QUANTITY
    });
  });

  describe("Stock Updates", () => {
    beforeEach(() => {
      // Initialize inventory for tests
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Test Produce"),
          Cl.uint(100),
          Cl.uint(2000),
          Cl.uint(20),
          Cl.stringAscii("Test Farm")
        ],
        farmer1
      );
    });

    it("should update stock with harvest", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "update-stock",
        [
          Cl.stringAscii("Test Produce"),
          Cl.uint(50),
          Cl.stringAscii("harvest"),
          Cl.stringAscii("New harvest batch"),
          Cl.stringAscii("BATCH-001")
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.uint(150)); // New stock level
    });

    it("should update stock with spoilage", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "update-stock",
        [
          Cl.stringAscii("Test Produce"),
          Cl.uint(30),
          Cl.stringAscii("spoilage"),
          Cl.stringAscii("Weather damage"),
          Cl.stringAscii("SPOIL-001")
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.uint(70)); // Reduced stock level
    });

    it("should fail with insufficient stock for spoilage", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "update-stock",
        [
          Cl.stringAscii("Test Produce"),
          Cl.uint(150), // More than available
          Cl.stringAscii("spoilage"),
          Cl.stringAscii("Too much spoilage"),
          Cl.stringAscii("FAIL-001")
        ],
        farmer1
      );

      expect(result).toBeErr(Cl.uint(117)); // ERR-INSUFFICIENT-STOCK
    });

    it("should fail with non-existent inventory", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "update-stock",
        [
          Cl.stringAscii("Nonexistent Produce"),
          Cl.uint(10),
          Cl.stringAscii("harvest"),
          Cl.stringAscii("Update attempt"),
          Cl.stringAscii("FAIL-002")
        ],
        farmer1
      );

      expect(result).toBeErr(Cl.uint(116)); // ERR-INVENTORY-NOT-FOUND
    });
  });

  describe("Stock Reservation", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Reserve Test"),
          Cl.uint(100),
          Cl.uint(2000),
          Cl.uint(10),
          Cl.stringAscii("Test Farm")
        ],
        farmer1
      );
    });

    it("should reserve stock successfully", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "reserve-stock",
        [
          Cl.stringAscii("Reserve Test"),
          Cl.uint(25)
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to reserve more than available", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "reserve-stock",
        [
          Cl.stringAscii("Reserve Test"),
          Cl.uint(150) // More than available
        ],
        farmer1
      );

      expect(result).toBeErr(Cl.uint(117)); // ERR-INSUFFICIENT-STOCK
    });

    it("should release reserved stock", () => {
      // First reserve some stock
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "reserve-stock",
        [
          Cl.stringAscii("Reserve Test"),
          Cl.uint(30)
        ],
        farmer1
      );

      // Then release it
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "release-reserved-stock",
        [
          Cl.stringAscii("Reserve Test"),
          Cl.uint(20)
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to release more than reserved", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "release-reserved-stock",
        [
          Cl.stringAscii("Reserve Test"),
          Cl.uint(50) // Nothing is reserved
        ],
        farmer1
      );

      expect(result).toBeErr(Cl.uint(117)); // ERR-INSUFFICIENT-STOCK
    });
  });

  describe("Stock Alerts", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Alert Test"),
          Cl.uint(50),
          Cl.uint(2000),
          Cl.uint(20), // Low threshold
          Cl.stringAscii("Alert Farm")
        ],
        farmer1
      );
    });

    it("should trigger low stock alert when threshold crossed", () => {
      // Reduce stock below threshold
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "update-stock",
        [
          Cl.stringAscii("Alert Test"),
          Cl.uint(35), // Reduces to 15, below threshold of 20
          Cl.stringAscii("spoilage"),
          Cl.stringAscii("Triggers alert"),
          Cl.stringAscii("ALERT-001")
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.uint(15)); // Should still complete successfully
    });

    it("should resolve stock alert", () => {
      // First trigger an alert by reducing stock
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "update-stock",
        [
          Cl.stringAscii("Alert Test"),
          Cl.uint(35),
          Cl.stringAscii("spoilage"),
          Cl.stringAscii("Create alert"),
          Cl.stringAscii("ALERT-002")
        ],
        farmer1
      );

      // Then resolve the alert
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "resolve-stock-alert",
        [
          Cl.uint(1) // Alert ID
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to resolve alert by non-farmer", () => {
      // Trigger an alert
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "update-stock",
        [
          Cl.stringAscii("Alert Test"),
          Cl.uint(35),
          Cl.stringAscii("spoilage"),
          Cl.stringAscii("Create alert"),
          Cl.stringAscii("ALERT-003")
        ],
        farmer1
      );

      // Try to resolve as different user
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "resolve-stock-alert",
        [
          Cl.uint(1)
        ],
        buyer1
      );

      expect(result).toBeErr(Cl.uint(100)); // ERR-NOT-AUTHORIZED
    });
  });

  describe("Batch Operations", () => {
    beforeEach(() => {
      // Initialize multiple produce types
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Tomatoes"),
          Cl.uint(100),
          Cl.uint(2000),
          Cl.uint(10),
          Cl.stringAscii("Farm A")
        ],
        farmer1
      );

      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Carrots"),
          Cl.uint(200),
          Cl.uint(2000),
          Cl.uint(20),
          Cl.stringAscii("Farm A")
        ],
        farmer1
      );
    });

    it("should process batch updates successfully", () => {
      const updates = Cl.list([
        Cl.tuple({
          "produce-type": Cl.stringAscii("Tomatoes"),
          "quantity": Cl.uint(25),
          "movement-type": Cl.stringAscii("harvest"),
          "reason": Cl.stringAscii("Batch harvest 1")
        }),
        Cl.tuple({
          "produce-type": Cl.stringAscii("Carrots"),
          "quantity": Cl.uint(50),
          "movement-type": Cl.stringAscii("harvest"),
          "reason": Cl.stringAscii("Batch harvest 2")
        })
      ]);

      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "batch-update-stock",
        [updates],
        farmer1
      );

      expect(result).toBeOk(
        Cl.list([
          Cl.ok(Cl.uint(125)), // Tomatoes: 100 + 25
          Cl.ok(Cl.uint(250))  // Carrots: 200 + 50
        ])
      );
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Read Test"),
          Cl.uint(150),
          Cl.uint(2000),
          Cl.uint(25),
          Cl.stringAscii("Read Farm")
        ],
        farmer1
      );
    });

    it("should get inventory information", () => {
      const { result } = simnet.callReadOnlyFn(
        "Produce-Pre-Sale-Platform-",
        "get-inventory",
        [
          Cl.principal(farmer1),
          Cl.stringAscii("Read Test")
        ],
        farmer1
      );

      expect(result).toBeOk(
        Cl.some(Cl.tuple({
          "current-stock": Cl.uint(150),
          "reserved-stock": Cl.uint(0),
          "available-stock": Cl.uint(150),
          "total-harvested": Cl.uint(150),
          "expiry-date": Cl.uint(2000),
          "reorder-threshold": Cl.uint(25),
          "last-updated": Cl.uint(simnet.blockHeight),
          "location": Cl.stringAscii("Read Farm")
        }))
      );
    });

    it("should return none for non-existent inventory", () => {
      const { result } = simnet.callReadOnlyFn(
        "Produce-Pre-Sale-Platform-",
        "get-inventory",
        [
          Cl.principal(farmer1),
          Cl.stringAscii("Nonexistent")
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.none());
    });

    it("should check if produce is expired", () => {
      const { result } = simnet.callReadOnlyFn(
        "Produce-Pre-Sale-Platform-",
        "is-produce-expired",
        [
          Cl.principal(farmer1),
          Cl.stringAscii("Read Test")
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.bool(false)); // Not expired yet
    });

    it("should calculate inventory value", () => {
      const { result } = simnet.callReadOnlyFn(
        "Produce-Pre-Sale-Platform-",
        "calculate-inventory-value",
        [
          Cl.principal(farmer1),
          Cl.stringAscii("Read Test"),
          Cl.uint(1000000) // 1 STX per unit
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.uint(150000000)); // 150 units * 1 STX
    });
  });

  describe("Authorization Tests", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Auth Test"),
          Cl.uint(100),
          Cl.uint(2000),
          Cl.uint(10),
          Cl.stringAscii("Auth Farm")
        ],
        farmer1
      );
    });

    it("should fail when non-farmer tries to update stock", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "update-stock",
        [
          Cl.stringAscii("Auth Test"),
          Cl.uint(10),
          Cl.stringAscii("harvest"),
          Cl.stringAscii("Unauthorized attempt"),
          Cl.stringAscii("FAIL-AUTH")
        ],
        buyer1 // Different user
      );

      expect(result).toBeErr(Cl.uint(116)); // ERR-INVENTORY-NOT-FOUND (farmer-specific)
    });

    it("should allow farmer to manage their own inventory", () => {
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "reserve-stock",
        [
          Cl.stringAscii("Auth Test"),
          Cl.uint(15)
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("Edge Cases", () => {
    it("should handle zero quantity validation", () => {
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Edge Test"),
          Cl.uint(50),
          Cl.uint(2000),
          Cl.uint(5),
          Cl.stringAscii("Edge Farm")
        ],
        farmer1
      );

      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "update-stock",
        [
          Cl.stringAscii("Edge Test"),
          Cl.uint(0), // Zero quantity
          Cl.stringAscii("harvest"),
          Cl.stringAscii("Zero update"),
          Cl.stringAscii("ZERO-001")
        ],
        farmer1
      );

      expect(result).toBeErr(Cl.uint(118)); // ERR-INVALID-QUANTITY
    });

    it("should handle exact threshold scenarios", () => {
      simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "initialize-inventory",
        [
          Cl.stringAscii("Threshold Test"),
          Cl.uint(30),
          Cl.uint(2000),
          Cl.uint(20),
          Cl.stringAscii("Threshold Farm")
        ],
        farmer1
      );

      // Reduce to exactly threshold level
      const { result } = simnet.callPublicFn(
        "Produce-Pre-Sale-Platform-",
        "update-stock",
        [
          Cl.stringAscii("Threshold Test"),
          Cl.uint(10), // Reduces to exactly 20
          Cl.stringAscii("spoilage"),
          Cl.stringAscii("Exact threshold"),
          Cl.stringAscii("THRESHOLD-001")
        ],
        farmer1
      );

      expect(result).toBeOk(Cl.uint(20));
    });
  });
});
