# @version 0.3.10

"""
@title Curve Limit Order Bot
@license Apache 2.0
@author Volume.finance
"""

struct Deposit:
    route: address[11]
    swap_params: uint256[5][5]
    amount: uint256
    pools: address[5]
    depositor: address

enum WithdrawType:
    CANCEL
    PROFIT_TAKING
    STOP_LOSS
    EXPIRE

interface ERC20:
    def balanceOf(_owner: address) -> uint256: view

interface WrappedEth:
    def deposit(): payable

interface CurveSwapRouter:
    def exchange(_route: address[11], _swap_params: uint256[5][5], _amount: uint256, _expected: uint256, _pools: address[5], _receiver: address) -> uint256: payable

event Deposited:
    deposit_id: uint256
    token0: address
    token1: address
    amount0: uint256
    depositor: address
    profit_taking: uint256
    stop_loss: uint256
    expire: uint256

event Withdrawn:
    deposit_id: uint256
    withdrawer: address
    withdraw_type: WithdrawType
    withdraw_amount: uint256

event UpdateCompass:
    old_compass: address
    new_compass: address

event UpdateRefundWallet:
    old_refund_wallet: address
    new_refund_wallet: address

event UpdateFee:
    old_fee: uint256
    new_fee: uint256

event SetPaloma:
    paloma: bytes32

event UpdateServiceFeeCollector:
    old_service_fee_collector: address
    new_service_fee_collector: address

event UpdateServiceFee:
    old_service_fee: uint256
    new_service_fee: uint256

VETH: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE # Virtual ETH
MAX_SIZE: constant(uint256) = 8
DENOMINATOR: constant(uint256) = 10000
ROUTER: immutable(address)
compass: public(address)
deposit_size: public(uint256)
deposits: public(HashMap[uint256, Deposit])
refund_wallet: public(address)
fee: public(uint256)
paloma: public(bytes32)
service_fee_collector: public(address)
service_fee: public(uint256)

@external
def __init__(_compass: address, router: address, _refund_wallet: address, _fee: uint256, _service_fee_collector: address, _service_fee: uint256):
    self.compass = _compass
    ROUTER = router
    self.refund_wallet = _refund_wallet
    self.fee = _fee
    self.service_fee_collector = _service_fee_collector
    self.service_fee = _service_fee
    log UpdateCompass(empty(address), _compass)
    log UpdateRefundWallet(empty(address), _refund_wallet)
    log UpdateFee(0, _fee)
    log UpdateServiceFeeCollector(empty(address), _service_fee_collector)
    log UpdateServiceFee(0, _service_fee)

@internal
def _safe_approve(_token: address, _to: address, _value: uint256):
    _response: Bytes[32] = raw_call(
        _token,
        _abi_encode(_to, _value, method_id=method_id("approve(address,uint256)")),
        max_outsize=32
    )  # dev: failed approve
    if len(_response) > 0:
        assert convert(_response, bool) # dev: failed approve

@internal
def _safe_transfer(_token: address, _to: address, _value: uint256):
    _response: Bytes[32] = raw_call(
        _token,
        _abi_encode(_to, _value, method_id=method_id("transfer(address,uint256)")),
        max_outsize=32
    )  # dev: failed transfer
    if len(_response) > 0:
        assert convert(_response, bool) # dev: failed transfer

@internal
def _safe_transfer_from(_token: address, _from: address, _to: address, _value: uint256):
    _response: Bytes[32] = raw_call(
        _token,
        _abi_encode(_from, _to, _value, method_id=method_id("transferFrom(address,address,uint256)")),
        max_outsize=32
    )  # dev: failed transferFrom
    if len(_response) > 0:
        assert convert(_response, bool) # dev: failed transferFrom

@external
@payable
@nonreentrant("lock")
def deposit(route: address[11], swap_params: uint256[5][5], amount: uint256, pools: address[5], profit_taking: uint256, stop_loss: uint256, expire: uint256):
    assert block.timestamp < expire, "Invalidated expire"
    _value: uint256 = msg.value
    assert self.paloma != empty(bytes32), "Paloma not set"
    _fee: uint256 = self.fee
    if _fee > 0:
        assert _value >= _fee, "Insufficient fee"
        send(self.refund_wallet, _fee)
        _value = unsafe_sub(_value, _fee)
    if route[0] == VETH:
        assert _value >= amount, "Insufficient deposit"
        if _value > amount:
            send(msg.sender, unsafe_sub(_value, amount))
    else:
        send(msg.sender, _value)
        self._safe_transfer_from(route[0], msg.sender, self, amount)
    deposit: Deposit = Deposit({
        route: route,
        swap_params: swap_params,
        amount: amount,
        pools: pools,
        depositor: msg.sender
    })
    last_token: address = empty(address)
    for i in range(4):
        last_token = deposit.route[8 - i * 2]
        if last_token != empty(address):
            break
    deposit_id: uint256 = self.deposit_size
    self.deposits[deposit_id] = deposit
    self.deposit_size = unsafe_add(deposit_id, 1)
    log Deposited(deposit_id, route[0], last_token, amount, msg.sender, profit_taking, stop_loss, expire)

@internal
@nonreentrant("lock")
def _withdraw(deposit_id: uint256, expected: uint256, withdraw_type: WithdrawType) -> uint256:
    deposit: Deposit = self.deposits[deposit_id]
    assert deposit.amount > 0, "Empty deposit"
    if withdraw_type == WithdrawType.CANCEL:
        assert msg.sender == deposit.depositor or msg.sender == empty(address), "Unauthorized"
    self.deposits[deposit_id] = Deposit({
        route: empty(address[11]),
        swap_params: empty(uint256[5][5]),
        amount: empty(uint256),
        pools: empty(address[5]),
        depositor: empty(address)
    })
    service_fee_amount: uint256 = 0
    _service_fee: uint256 = self.service_fee
    if withdraw_type == WithdrawType.CANCEL or withdraw_type == WithdrawType.EXPIRE:
        if _service_fee > 0:
            service_fee_amount = unsafe_div(deposit.amount * _service_fee, DENOMINATOR)
        actual_amount: uint256 = unsafe_sub(deposit.amount, service_fee_amount)
        if deposit.route[0] == VETH:
            send(deposit.depositor, actual_amount)
            if service_fee_amount > 0:
                send(self.service_fee_collector, service_fee_amount)
        else:
            self._safe_transfer(deposit.route[0], deposit.depositor, actual_amount)
            if service_fee_amount > 0:
                self._safe_transfer(deposit.route[0], self.service_fee_collector, service_fee_amount)
        log Withdrawn(deposit_id, msg.sender, withdraw_type, actual_amount)
        return deposit.amount
    else:
        last_token: address = empty(address)
        for i in range(4):
            last_token = deposit.route[8 - i * 2]
            if last_token != empty(address):
                break
        amount0: uint256 = 0
        actual_amount: uint256 = 0
        if deposit.route[0] == VETH:
            amount0 = CurveSwapRouter(ROUTER).exchange(deposit.route, deposit.swap_params, deposit.amount, expected, deposit.pools, self, value=deposit.amount)
            if _service_fee > 0:
                service_fee_amount = unsafe_div(amount0 * _service_fee, DENOMINATOR)
            actual_amount = unsafe_sub(amount0, service_fee_amount)
            if last_token == VETH:
                send(deposit.depositor, actual_amount)
                if service_fee_amount > 0:
                    send(self.service_fee_collector, service_fee_amount)
            else:
                self._safe_transfer(last_token, deposit.depositor, actual_amount)
                if service_fee_amount > 0:
                    self._safe_transfer(last_token, self.service_fee_collector, service_fee_amount)
        else:
            self._safe_approve(deposit.route[0], ROUTER, deposit.amount)
            amount0 = CurveSwapRouter(ROUTER).exchange(deposit.route, deposit.swap_params, deposit.amount, expected, deposit.pools, self)
            if _service_fee > 0:
                service_fee_amount = unsafe_div(amount0 * _service_fee, DENOMINATOR)
            actual_amount = unsafe_sub(amount0, service_fee_amount)
            if last_token == VETH:
                send(deposit.depositor, actual_amount)
                if service_fee_amount > 0:
                    send(self.service_fee_collector, service_fee_amount)
            else:
                self._safe_transfer(last_token, deposit.depositor, actual_amount)
                if service_fee_amount > 0:
                    self._safe_transfer(last_token, self.service_fee_collector, service_fee_amount)
        log Withdrawn(deposit_id, msg.sender, withdraw_type, actual_amount)
        return amount0

@external
def cancel(deposit_id: uint256, expected: uint256) -> uint256:
    return self._withdraw(deposit_id, expected, WithdrawType.CANCEL)

@external
def multiple_withdraw(deposit_ids: DynArray[uint256, MAX_SIZE], expected: DynArray[uint256, MAX_SIZE], withdraw_types: DynArray[WithdrawType, MAX_SIZE]):
    assert msg.sender == self.compass, "Unauthorized"
    _len: uint256 = len(deposit_ids)
    assert _len == len(expected) and _len == len(withdraw_types), "Validation error"
    _len = unsafe_add(unsafe_mul(unsafe_add(_len, 2), 96), 36)
    assert len(msg.data) == _len, "invalid payload"
    assert self.paloma == convert(slice(msg.data, unsafe_sub(_len, 32), 32), bytes32), "invalid paloma"
    for i in range(MAX_SIZE):
        if i >= len(deposit_ids):
            break
        self._withdraw(deposit_ids[i], expected[i], withdraw_types[i])

@external
def withdraw(deposit_id: uint256, withdraw_type: WithdrawType) -> uint256:
    assert msg.sender == empty(address) # this will work as a view function only
    return self._withdraw(deposit_id, 1, withdraw_type)

@external
def update_compass(new_compass: address):
    assert msg.sender == self.compass and len(msg.data) == 68 and convert(slice(msg.data, 36, 32), bytes32) == self.paloma, "Unauthorized"
    self.compass = new_compass
    log UpdateCompass(msg.sender, new_compass)

@external
def update_refund_wallet(new_refund_wallet: address):
    assert msg.sender == self.compass and len(msg.data) == 68 and convert(slice(msg.data, 36, 32), bytes32) == self.paloma, "Unauthorized"
    old_refund_wallet: address = self.refund_wallet
    self.refund_wallet = new_refund_wallet
    log UpdateRefundWallet(old_refund_wallet, new_refund_wallet)

@external
def update_fee(new_fee: uint256):
    assert msg.sender == self.compass and len(msg.data) == 68 and convert(slice(msg.data, 36, 32), bytes32) == self.paloma, "Unauthorized"
    old_fee: uint256 = self.fee
    self.fee = new_fee
    log UpdateFee(old_fee, new_fee)

@external
def set_paloma():
    assert msg.sender == self.compass and self.paloma == empty(bytes32) and len(msg.data) == 36, "Unauthorized"
    _paloma: bytes32 = convert(slice(msg.data, 4, 32), bytes32)
    self.paloma = _paloma
    log SetPaloma(_paloma)

@external
def update_service_fee_collector(new_service_fee_collector: address):
    assert msg.sender == self.service_fee_collector, "Unauthorized"
    self.service_fee_collector = new_service_fee_collector
    log UpdateServiceFeeCollector(msg.sender, new_service_fee_collector)

@external
def update_service_fee(new_service_fee: uint256):
    assert msg.sender == self.compass and len(msg.data) == 68 and convert(slice(msg.data, 36, 32), bytes32) == self.paloma, "Unauthorized"
    assert new_service_fee < DENOMINATOR
    old_service_fee: uint256 = self.service_fee
    self.service_fee = new_service_fee
    log UpdateServiceFee(old_service_fee, new_service_fee)

@external
@payable
def __default__():
    pass