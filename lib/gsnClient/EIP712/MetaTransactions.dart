import 'dart:convert';
import 'dart:typed_data';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter_sdk/contracts/erc20.dart';
import 'package:flutter_sdk/gsnClient/gsnTxHelpers.dart';
import 'package:flutter_sdk/gsnClient/utils.dart';
import 'package:flutter_sdk/utils/constants.dart';
import 'package:web3dart/web3dart.dart';
import 'package:convert/convert.dart';

import '../../network_config/network_config.dart'; // For the hex string conversion

class MetaTransaction {
  String? name;
  String? version;
  String? salt;
  String? verifyingContract;
  int nonce;
  String from;
  Uint8List functionSignature;

  MetaTransaction({
    this.name,
    this.version,
    this.salt,
    this.verifyingContract,
    required this.nonce,
    required this.from,
    required this.functionSignature,
  });
}

Map<String, dynamic> getTypedMetatransaction(MetaTransaction transaction) {
  return {
    "types": [
        {"name": "nonce", "type": "uint256"},
        {"name": "from", "type": "address"},
        {"name": "functionSignature", "type": "bytes"},
      ],
    "domain": {
      "name": transaction.name,
      "version": transaction.version,
      "verifyingContract": transaction.verifyingContract,
      "salt": transaction.salt,
    },
    "primaryType": "MetaTransaction",
    "message": {
      "nonce": transaction.nonce,
      "from": transaction.from,
      "functionSignature": transaction.functionSignature,
    },
  };
}

Future<Map<String, dynamic>> getMetatransactionEIP712Signature(
  Wallet account,
  String contractName,
  String contractAddress,
  Uint8List functionSignature,
  NetworkConfig config,
  int nonce,
) async {
  // name and chainId to be used in EIP712
  final chainId = config.gsn.chainId;

  // typed data for signing
  final eip712Data = getTypedMetatransaction(
    MetaTransaction(
      name: contractName,
      version: '1',
      salt: hexZeroPad(int.parse(chainId),32),
      // Padding the chainId with zeroes to make it 32 bytes
      verifyingContract: contractAddress,
      nonce: nonce,
      from: account.privateKey.address.hex,
      functionSignature: functionSignature,
    ),
  );

  // signature for metatransaction
  // signature for metatransaction
  final String signature = EthSigUtil.signTypedData(
      jsonData: jsonEncode(eip712Data), version: TypedDataVersion.V1);
  // get r,s,v from signature
  final signatureBytes = hex.decode(signature);
  return {
    'r': '0x${hex.encode(signatureBytes.sublist(0, 32))}',
    's': '0x${hex.encode(signatureBytes.sublist(32, 64))}',
    'v': signatureBytes[64] + 27,
  };
}

String hexZeroPad(int number, int length) {
  final hexString = hex.encode(Uint8List.fromList([number]));
  final paddedHexString = hexString.padLeft(length * 2, '0');
  return '0x$paddedHexString';
}


Future<bool> hasExecuteMetaTransaction(
  Wallet account,
  String destinationAddress,
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

    final nonce = await getSenderContractNonce(
        provider, token, account.privateKey.address);

    final funCall = await provider.call(
        contract: token, function: token.function("decimals"), params: []);
    final decimals = funCall[0];
    final decimalAmount = parseUnits(amount.toString(), int.parse(decimals.toString()));

    final data = token
        .function('transfer')
        .encodeCall([EthereumAddress.fromHex(destinationAddress), decimalAmount]);

    final signatureData = await getMetatransactionEIP712Signature(
      account,
      name,
      contractAddress,
      data,
      config,
      nonce.toInt(),
    );

    final executeMetaTransactionFunction = token.function('executeMetaTransaction');

    await provider
        .call(contract: token, function: executeMetaTransactionFunction, params: [
      account.privateKey.address,
      data,
      signatureData['r'],
      signatureData['s'],
      signatureData['v'],
      {"from": account.privateKey.address}
    ]);

    return true;
  } catch (e) {
    return false;
  }
}

Future<GsnTransactionDetails> getExecuteMetatransactionTx(
  Wallet account,
  String destinationAddress,
  double amount,
  NetworkConfig config,
  String contractAddress,
  Web3Client provider,
) async {
  //TODO: Once things are stable, think about refactoring
  // to avoid code duplication
  final token = erc20(contractAddress);
  final name = token.abi.name;
  final nonce = await provider.getTransactionCount(token.address);
  // final decimalAmount = BigInt.from(amount) * BigInt.from(10).pow(decimals);
  final decimalAmount = BigInt.from(amount) * BigInt.from(10);

  // get function signature
  final data = await provider.call(
      contract: token,
      function: token.function("transfer"),
      params: [EthereumAddress.fromHex(destinationAddress), decimalAmount]);

  final signatureData = await getMetatransactionEIP712Signature(
    account,
    name,
    contractAddress,
    data[0],
    config,
    nonce.toInt(),
  );

  final r = hex.decode(signatureData['r']);
  final s = hex.decode(signatureData['s']);
  final v = signatureData['v'];
  final tx = await provider.call(
      contract: token,
      function: token.function("executeMetaTransaction"),
      params: [
        EthereumAddress.fromHex(account.privateKey.address.hex),
        data,
        v,
        r,
        s
      ]);

  // final gas = await _estimateGasForMetaTransaction(
  //   token,
  //   EthereumAddress.fromHex(account.privateKey.address.hex),
  //   EthereumAddress.fromHex(config.gsn.paymasterAddress),
  //   decimalAmount,
  //   signatureData['v'],
  //   signatureData['r'],
  //   signatureData['s'],
  //   EthereumAddress.fromHex(account.privateKey.address.hex),
  //   'executeMetaTransaction',
  // );

  //following code is inspired from getFeeData method of
  //abstrac-provider of ethers js library
  final EtherAmount gasPrice = await provider.getGasPrice();
  final BigInt maxPriorityFeePerGas = BigInt.parse("1500000000");
  final maxFeePerGas =
      gasPrice.getInWei * BigInt.from(2) + (maxPriorityFeePerGas);
  if (tx == null || tx.isEmpty) {
    throw 'tx not populated';
  }

  final gsnTx = GsnTransactionDetails(
    from: account.privateKey.address.hex,
    data: tx[0],
    value: "0",
    to: token.address.hex,
    /* from the populateTransaction method of index.ts of ethers,
    we know that the to address here is the address of the contract*/
    // gas: '0x${gas.toHexString()}',
    gas: 'example',
    maxFeePerGas: maxFeePerGas.toString(),
    maxPriorityFeePerGas: maxPriorityFeePerGas.toString(),
  );
  return gsnTx;
}
