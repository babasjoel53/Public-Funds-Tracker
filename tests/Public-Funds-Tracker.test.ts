
import { describe, expect, it, beforeEach } from "vitest";
import { Cl as Cv } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const deployer = accounts.get("deployer")!;

describe("Public Funds Tracker", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  describe("Treasury Management", () => {
    it("allows owner to initialize treasury", () => {
      const { result } = simnet.callPublicFn(
        "Public-Funds-Tracker",
        "initialize-treasury",
        [Cv.uint(1000000)],
        deployer
      );
      expect(result).toBeOk(Cv.bool(true));
    });

    it("prevents non-owner from initializing treasury", () => {
      const { result } = simnet.callPublicFn(
        "Public-Funds-Tracker",
        "initialize-treasury",
        [Cv.uint(1000000)],
        address1
      );
      expect(result).toBeErr(Cv.uint(100)); // err-owner-only
    });
  });

  describe("Project Management", () => {
    beforeEach(() => {
      // Initialize treasury
      simnet.callPublicFn(
        "Public-Funds-Tracker",
        "initialize-treasury",
        [Cv.uint(1000000)],
        deployer
      );
    });

    it("allows owner to create project", () => {
      const { result } = simnet.callPublicFn(
        "Public-Funds-Tracker",
        "create-project",
        [
          Cv.stringAscii("Test Project"),
          Cv.stringAscii("Test Description"),
          Cv.uint(100000),
          Cv.principal(address1),
        ],
        deployer
      );
      expect(result).toBeOk(Cv.uint(1));
    });

    it("prevents creating project with insufficient funds", () => {
      const { result } = simnet.callPublicFn(
        "Public-Funds-Tracker",
        "create-project",
        [
          Cv.stringAscii("Test Project"),
          Cv.stringAscii("Test Description"),
          Cv.uint(2000000), // More than treasury balance
          Cv.principal(address1),
        ],
        deployer
      );
      expect(result).toBeErr(Cv.uint(103)); // err-insufficient-funds
    });
  });

});
