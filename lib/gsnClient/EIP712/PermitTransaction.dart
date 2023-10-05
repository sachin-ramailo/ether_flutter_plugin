import 'dart:convert';
import 'dart:typed_data';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:eth_sig_util/util/utils.dart';
import 'package:flutter_sdk/utils/constants.dart';
import 'package:web3dart/web3dart.dart';

import '../../contracts/erc20.dart';
import '../../network_config/network_config.dart';
import '../gsnTxHelpers.dart';
import '../utils.dart';

class Permit {
  String name;
  String version;
  String chainId;
  String verifyingContract;
  String owner;
  String spender;
  dynamic value;
  dynamic nonce;
  dynamic deadline;
  String salt;

  Permit({
    required this.name,
    required this.version,
    required this.chainId,
    required this.verifyingContract,
    required this.owner,
    required this.spender,
    required this.value,
    required this.nonce,
    required this.deadline,
    required this.salt,
  });
}

Map<String, dynamic> getTypedPermitTransaction(Permit permit) {
  return {
    'types': {
      'Permit': [
        {'name': 'owner', 'type': 'address'},
        {'name': 'spender', 'type': 'address'},
        {'name': 'value', 'type': 'uint256'},
        {'name': 'nonce', 'type': 'uint256'},
        {'name': 'deadline', 'type': 'uint256'},
      ],
      'EIP712Domain': [
        {'name': 'name', 'type': 'string'},
        {'name': 'version', 'type': 'string'},
        {"name": "chainId", "type": "uint256"},
        {'name': 'verifyingContract', 'type': 'address'},
        {'name': 'salt', 'type': 'bytes32'},
      ],
    },
    'primaryType': 'Permit',
    'domain': {
      'name': permit.name,
      'version': permit.version,
      'chainId': permit.chainId,
      'verifyingContract': permit.verifyingContract,
      if (permit.salt != '0x' && permit.salt.isNotEmpty) 'salt': permit.salt,
    },
    'message': {
      'owner': permit.owner,
      'spender': permit.spender,
      'value': permit.value.toString(),
      'nonce': permit.nonce.toString(),
      'deadline': permit.deadline.toString(),
    },
  };
}

Future<Map<String, dynamic>> getPermitEIP712Signature(
  Wallet account,
  String contractName,
  String contractAddress,
  NetworkConfig config,
  int nonce,
  BigInt amount,
  BigInt deadline,
  Uint8List salt,
) async {
  // chainId to be used in EIP712
  final chainId = config.gsn.chainId;

  // typed data for signing
  final eip712Data = getTypedPermitTransaction(
    Permit(
      name: contractName,
      version: '1',
      chainId: chainId,
      verifyingContract: contractAddress,
      owner: account.privateKey.address.hex,
      spender: config.gsn.paymasterAddress,
      value: amount.toString(),
      nonce: nonce.toString(),
      deadline: deadline.toString(),
      salt: "0x${bytesToHex(salt)}",
    ),
  );

  // signature for metatransaction
  final String signature = EthSigUtil.signTypedData(
    jsonData: jsonEncode(eip712Data),
    version: TypedDataVersion.V4,
    privateKey: "0x${bytesToHex(account.privateKey.privateKey)}",
  );
  printLog('Signature from Permit tx : $signature');

  final cleanedSignature =
      signature.startsWith('0x') ? signature.substring(2) : signature;
  final signatureBytes = hexToBytes(cleanedSignature);

  final r = signatureBytes.sublist(0, 32);
  final s = signatureBytes.sublist(32, 64);
  int v = signatureBytes[64];

  printLog("r from permit txn= $r");
  printLog("s from permit txn= $s");
  printLog("v from permit txn= $v");

  return {
    'r': r,
    's': s,
    'v': v,
  };
}

Future<bool> hasPermit(
  Wallet account,
  double amount,
  NetworkConfig config,
  String contractAddress,
  Web3Client provider,
) async {
  try {
    final token = erc20(contractAddress);

    final nameCall = await provider
        .call(contract: token, function: token.function('name'), params: []);
    final name = nameCall[0];
    final noncesFunctionCall = await provider.call(
        contract: token,
        function: token.function('nonces'),
        params: [account.privateKey.address]);
    final nonce = noncesFunctionCall[0] as BigInt;
    final nonceInt = nonce.toInt();

    final deadline = await getPermitDeadline(provider);
    final eip712Domain = await provider.call(
        contract: token, function: token.function('eip712Domain'), params: []);

    final salt =
        /*5 is hardcoded here because in the erc20 json,
    the salt appears on 5th index in outputs
    of function eip712Domain*/
        eip712Domain[5];

    //TODO: the amount can be in points eg: 0.5 fix it once permit txn start going through
    int amt = amount.toInt();
    final decimalAmount =
        EtherAmount.fromBase10String(EtherUnit.ether, amt.toString());
    final signature = await getPermitEIP712Signature(
      account,
      name,
      contractAddress,
      config,
      nonceInt,
      decimalAmount.getInWei,
      deadline,
      salt,
    );
    provider
        .call(contract: token, function: token.function('name'), params: []);

    await _estimateGasForPermit(
      token,
      account.privateKey.address,
      EthereumAddress.fromHex(config.gsn.paymasterAddress),
      decimalAmount.getInWei,
      deadline,
      signature['v'],
      signature['r'],
      signature['s'],
      provider,
      EthereumAddress.fromHex(account.privateKey.address.hex),
    );

    return true;
  } catch (e) {
    return false;
  }
}

Future<BigInt> _estimateGasForPermit(
    DeployedContract token,
    EthereumAddress accountAddress,
    EthereumAddress paymasterAddress,
    BigInt decimalAmount,
    BigInt deadline,
    int v,
    Uint8List r,
    Uint8List s,
    Web3Client provider,
    EthereumAddress fromAddress) async {
  try {
    final function = token.function('permit');
    final args = [
      accountAddress,
      paymasterAddress,
      decimalAmount,
      deadline,
      BigInt.from(v),
      r,
      s
    ];

    // Create a list of arguments to pass to the function
    final data = function.encodeCall(args);

// Estimate the gas required for the transaction
    final gasEstimate = await provider.estimateGas(
      sender: fromAddress,
      data: data,
      to: token.address,
    );

    return gasEstimate;
  } catch (e) {
    rethrow;
  }
}

Future<GsnTransactionDetails> getPermitTx(
  Wallet account,
  EthereumAddress destinationAddress,
  double amount,
  NetworkConfig config,
  String contractAddress,
  Web3Client provider,
) async {
  final token = erc20(contractAddress);
  final noncesCallResult = await provider.call(
      contract: token,
      function: token.function("nonces"),
      params: [account.privateKey.address]);

  final nameCall = await provider
      .call(contract: token, function: token.function('name'), params: []);
  final name = nameCall.first;
  final nonce = noncesCallResult[0] as BigInt;

  final decimalsCallResult = await provider
      .call(contract: token, function: token.function("decimals"), params: []);
  final decimals = decimalsCallResult[0];

  final deadline = await getPermitDeadline(provider);
  final eip712DomainCallResult = await provider.call(
      contract: token, function: token.function('eip712Domain'), params: []);

  final salt =
      /*5 is hardcoded here because in the erc20 json,
    the salt appears on 5th index in outputs
    of function eip712Domain*/
      eip712DomainCallResult[5];

  final decimalAmount =
      parseUnits(amount.toString(), int.parse(decimals.toString()));

  final signature = await getPermitEIP712Signature(
    account,
    name,
    contractAddress,
    config,
    nonce.toInt(),
    decimalAmount,
    deadline,
    salt,
  );

  final tx = Transaction.callContract(
      contract: token,
      function: token.function('permit'),
      parameters: [
        account.privateKey.address,
        EthereumAddress.fromHex(config.gsn.paymasterAddress),
        decimalAmount,
        deadline,
        BigInt.from(signature['v']),
        signature['r'],
        signature['s'],
      ]);

  final gas = await _estimateGasForPermit(
    token,
    account.privateKey.address,
    EthereumAddress.fromHex(config.gsn.paymasterAddress),
    decimalAmount,
    deadline,
    signature['v'],
    signature['r'],
    signature['s'],
    provider,
    EthereumAddress.fromHex(account.privateKey.address.hex),
  );

  final fromTx = Transaction.callContract(
      contract: token,
      function: token.function('transferFrom'),
      parameters: [
        account.privateKey.address,
        destinationAddress,
        decimalAmount,
      ]);

  final fromTxDataInString = bytesToHex(fromTx.data!);

  final paymasterData =
      '0x${token.address.hex.replaceFirst('0x', '')}${fromTxDataInString.replaceFirst('0x', '')}';
  //following code is inspired from getFeeData method of
  //abstract-provider of ethers js library
  final EtherAmount gasPrice = await provider.getGasPrice();
  final BigInt maxPriorityFeePerGas = BigInt.parse("1500000000");
  final maxFeePerGas =
      gasPrice.getInWei * BigInt.from(2) + (maxPriorityFeePerGas);

  final gsnTx = GsnTransactionDetails(
    from: account.privateKey.address.hex,
    data: "0x${bytesToHex(tx.data!)}",
    value: "0",
    to: tx.to!.hex,
    gas: "0x${gas.toRadixString(16)}",
    maxFeePerGas: maxFeePerGas.toString(),
    maxPriorityFeePerGas: maxPriorityFeePerGas.toString(),
    paymasterData: paymasterData,
  );

  return gsnTx;
}

// get timestamp that will always be included in the next 3 blocks
Future<BigInt> getPermitDeadline(Web3Client provider) async {
  final block = await provider.getBlockInformation();
  return BigInt.from(
      block.timestamp.add(const Duration(seconds: 45)).millisecondsSinceEpoch);
}
