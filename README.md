# 📬 `PostMaster`

**CAUTION**: This contract is **NOT** audited. Use at your own risk.

This is a helper contract that can be used to atomically purchase a batch of stamps for [Swarm](https://ethswarm.org) using xDAI as the input.

Steps to use:

1. First get a quote for the batch you want to purchase.
2. Call `purchase` or `purchaseMany` setting the required amount of xDAI in `tx.value`.

The contract has been deployed on [Gnosis Chain](https://gnosischain.com) at [`0x5D10aA4B01A43eeFAA45fE0CD01c9bF5958615bC`](https://gnosisscan.io/address/0x5D10aA4B01A43eeFAA45fE0CD01c9bF5958615bC).
