# Koala Real World Asset Platform

**Koala Real World Asset (RWA)** is a blockchain-based platform designed to bridge real-world assets with liquidity in the decentralized finance (DeFi) ecosystem. By tokenizing real-world assets as NFTs and integrating them into pools, Koala RWA enables investors to access a diversified range of real-world collateral while allowing borrowers (originators) to raise capital against these tokenized assets.

## Key Actors and Roles

1. **Pool Admin**:  
   - Responsible for creating and managing multiple pools of assets.
   - Issues two types of tokens to investors:
     - **Senior Obligations Tokens (SOT)**: These represent a lower-risk, more stable investment option, typically providing a fixed return.
     - **Junior Obligations Tokens (JOT)**: These offer higher risk but potentially higher returns, as they are subordinate to SOT in terms of payouts.
   - Configures the **risk score** system, which determines the risk profile of the pool, affecting investment strategies.
   - Manages other pool parameters such as loan-to-value (LTV) ratios, interest rates, and duration of loans.

2. **Borrower/Originator**:  
   - Individuals or institutions that upload real-world assets (such as real estate, invoices, luxury items like diamonds) into the platform.
   - These assets are tokenized as **NFTs**, representing the ownership and value of the real-world asset on-chain.
   - Borrows funds from investors by pledging these tokenized assets as collateral, receiving liquidity in return.
   - Repays the loan with interest over time, which increases the value of the SOT and JOT held by investors.

3. **Investor**:  
   - Provides liquidity to the platform by purchasing **SOT** and **JOT** tokens within a specific pool.
   - The tokens represent fractional ownership of the pool's assets and entitle the holder to a share of the profits.
   - Investors choose between SOT (low risk, stable returns) or JOT (higher risk, potential for greater returns).
   - Upon repayment by the borrower, the interest accrued increases the value of the pool, benefiting the investors.
   - Investors can exit their positions by selling their tokens back to the pool or on secondary markets, allowing liquidity realization.

## Platform Workflow

1. **Pool Creation**:  
   Pool admins create pools with specific parameters, including interest rates, risk score metrics, and token issuance strategies (SOT and JOT). Each pool may have a different risk profile based on the assets held and the borrower’s creditworthiness.

2. **Asset Tokenization**:  
   Borrowers upload their real-world assets to the platform, which are then verified and tokenized as **NFTs**. Each NFT represents a unique real-world asset that is used as collateral in the borrowing process.

3. **Investment**:  
   Investors participate in the pool by purchasing SOT or JOT tokens based on their risk appetite. These tokens represent their claim on the pool’s assets and the interest payments made by borrowers.

4. **Loan Upload**:  
   Borrowers receive liquidity from the pool, secured against the NFTs representing their real-world assets. The loan terms (interest rate, repayment schedule) are predefined by the pool’s parameters.

5. **Repayment and Returns**:  
   Borrowers make periodic interest payments, which are distributed to the pool’s investors. The value of the SOT and JOT tokens appreciates over time as the interest accumulates. When the loan is fully repaid, the NFT is released, and investors can realize their profits by selling their tokens.

## Why Aptos Blockchain?

Aptos blockchain technology plays a crucial role in powering the Koala RWA platform by providing a secure, scalable, and developer-friendly infrastructure. Here's how Aptos enhances the platform:

- **On-Chain Security**:  
  The Aptos blockchain ensures a high level of security with its built-in **re-entrancy guard**, which prevents common smart contract attacks such as re-entrancy attacks. This feature guarantees that assets and tokens stored in the pools remain safe from malicious activity.

- **Account Resources for Multi-Pool Creation**:  
  Aptos allows the creation of multiple pools using its innovative **account resources** system. This enables Pool Admins to easily manage and track various pools, each with different parameters, under a single account without needing to deploy separate smart contracts for each pool.

- **Fast and Reliable Devnet/Testnet**:  
  Aptos provides a **fast, stable Devnet/Testnet** that supports rapid development and deployment of decentralized applications. The performance of Aptos ensures that transactions related to the creation, management, and liquidation of pools happen efficiently and cost-effectively. The Devnet/Testnet also allows developers to test new features before deploying them to the mainnet, ensuring robustness and reliability.

- **Community Support and Ecosystem**:  
  The vibrant and supportive Aptos developer community provides valuable resources, documentation, and tools that accelerate development, allowing the Koala RWA platform to evolve rapidly.

## Aptos Testnet deployed address
| **Item**         | **Details**                                                                 |
|------------------|------------------------------------------------------------------------------|
| **Module Address** | `0x0c25ff16f4bac53ad93930edba398b2db2904faa7146981d7ab563fdd6100819`        |
| **USD-peg**       | `0xc4d3219d01d6f9c091c949e3d0533d7aece05cf1a2dfa333b5af9e93fd780e1c`         |
| **Pool Example**  | `0x6235dc1fc91ec3a759ea661cdcbfc0a5666b20017d9171ffa3af4b8bc1963ff3`         |
| **RPC**           | [https://fullnode.testnet.aptoslabs.com](https://fullnode.testnet.aptoslabs.com) |
| **Faucet URL**    | [https://faucet.testnet.aptoslabs.com](https://faucet.testnet.aptoslabs.com)  |
