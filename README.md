# UnicornMarket

Fully onchain orderbook for Unicorn ecosystem trading.

## Primary v1 market path
- **Unicorn (unwrapped)** ⇄ **Wrapped Unicorn Meat (wMEAT)**

Secondary compatibility paths (wrapped Unicorn / unwrapped Meat) are supported but not the primary UX focus.

## Why this exists
- Grinder revival is blocked pending upstream decision.
- AMM pooling is awkward with 0-decimal legacy tokens.
- UnicornMarket provides transparent, cancellable, onchain bids/asks with event logs.

## Contract
- `src/UnicornMarket.sol`
- Hardcoded canonical token set (no arbitrary token addresses)
- Core actions: place order, partial/full fill, cancel
- Ledger via events: `OrderPlaced`, `OrderFilled`, `OrderCancelled`

## Testing

### Unit/fork tests
```bash
forge test
```

### Mainnet fork (recommended)
```bash
MAINNET_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/<KEY>" forge test -vv
```

This suite validates behavior against real deployed contracts on an Ethereum mainnet fork.

## UI mock
- `ui-mock/index.html` (mock data only)
- Mobile + desktop orderbook/ledger/trade layout for review
