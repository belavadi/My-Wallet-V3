const Web3 = require('web3');
const web3 = new Web3();

class EthWalletTx {
  constructor (obj) {
    this._blockNumber = obj.blockNumber;
    this._timeStamp = obj.timeStamp;
    this._hash = obj.hash;
    this._from = obj.from;
    this._to = obj.to;
    this._value = obj.value;
    this._gas = obj.gas;
    this._gasPrice = obj.gasPrice;
    this._gasUsed = obj.gasUsed;
    this._confirmations = 0;
  }

  get amount () {
    return web3.fromWei(this._value, 'ether');
  }

  get fee () {
    let weiUsed = web3.toBigNumber(this._gasPrice).mul(this._gasUsed);
    return web3.fromWei(weiUsed, 'ether').toString();
  }

  get to () {
    return this._to;
  }

  get from () {
    return this._from;
  }

  get hash () {
    return this._hash;
  }

  get time () {
    return this._timeStamp;
  }

  get confirmations () {
    return this._confirmations;
  }

  isFromAccount (account) {
    return this._from === account.address;
  }

  updateConfirmations (latestBlock) {
    this._confirmations = latestBlock - this._blockNumber;
  }

  static txTimeSort (txA, txB) {
    return txB.time - txA.time;
  }

  static fromJSON (json) {
    return new EthWalletTx(json);
  }
}

module.exports = EthWalletTx;