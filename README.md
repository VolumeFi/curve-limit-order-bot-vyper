# Limit Order Bot Vyper for Curve

## Read-Only functions

### compass

| Key        | Type    | Description                                |
| ---------- | ------- | ------------------------------------------ |
| **Return** | address | Returns compass-evm smart contract address |

### admin

| Key        | Type    | Description              |
| ---------- | ------- | ------------------------ |
| **Return** | address | Returns an admin address |

### deposit_size

| Key        | Type    | Description                       |
| ---------- | ------- | --------------------------------- |
| **Return** | uint256 | Returns deposit list current size |

### deposits

| Key        | Type    | Description                           |
| ---------- | ------- | ------------------------------------- |
| *arg0*     | uint256 | Deposit Id to get Deposit information |
| **Return** | Deposit | Deposit information                   |


## State-Changing functions

### deposit

Deposit a token with its amount with an expected token address and amount. This is run by users. Refer [Curve Vyper Contract](https://github.com/curvefi/curve-pool-registry/blob/0bdb116024ccacda39295bb3949c3e6dd0a8e2d9/contracts/Swaps.vy#L497) for Curve swap params.

| Key           | Type          | Description                       |
| ------------- | ------------- | --------------------------------- |
| route         | address[9]    | Curve swap route                  |
| swap_params   | uint256[3][4] | Curve swap parameters             |
| amount        | uint256       | deposit amount                    |
| pools         | address[4]    | Curve swap pool of meta-factories |
| profit_taking | uint256       | Permille of profit_taking         |
| stop_loss     | uint256       | Permille of stop_loss             |
| expire        | uint256       | Expire timestamp                  |

### cancel

Cancel order. This is run by users.

| Key        | Type    | Description                                           |
| ---------- | ------- | ----------------------------------------------------- |
| deposit_id | uint256 | Deposit Id to cancel                                  |
| expected   | uint256 | Mininum amount of expected token to receive on cancel |

### withdraw

Swap and send the token to the depositor. This is run by Compass-EVM only.

| Key           | Type         | Description                                             |
| ------------- | ------------ | ------------------------------------------------------- |
| deposit_id    | uint256      | Deposit Id to swap and send to the depositor            |
| expected      | uint256      | Mininum amount of expected token to receive on withdraw |
| withdraw_type | WithdrawType | Withdraw type enum value                                |

### multiple_withdraw

Swap and send multiple tokens to the depositor. This is run by Compass-EVM only.

| Key            | Type           | Description                                                   |
| -------------- | -------------- | ------------------------------------------------------------- |
| deposit_ids    | uint256[]      | Deposit Id array to swap and send to the depositor            |
| expected       | uint256[]      | Mininum amount array of original token to receive on withdraw |
| withdraw_types | WithdrawType[] | Withdraw type enum value array                                |

### update_compass

Update Compass-EVM address.  This is run by Compass-EVM only.

| Key         | Type    | Description             |
| ----------- | ------- | ----------------------- |
| new_compass | address | New compass-evm address |

## Struct

### Deposit

| Key         | Type          | Description                       |
| ----------- | ------------- | --------------------------------- |
| route       | address[9]    | Curve swap route                  |
| swap_params | uint256[3][4] | Curve swap parameters             |
| amount      | uint256       | deposit amount                    |
| pools       | address[4]    | Curve swap pool of meta-factories |
| depositor   | address       | Depositor address                 |

## Enum

### WithdrawType

| Key           | Description   |
| ------------- | ------------- |
| CANCEL        | Cancel order  |
| PROFIT_TAKING | Profit taking |
| STOP_LOSS     | Stop loss     |
| EXPIRE        | Expire cancel |