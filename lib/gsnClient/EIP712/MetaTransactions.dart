import 'dart:convert';
import 'dart:typed_data';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:eth_sig_util/util/utils.dart';
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

Map<String, dynamic> getTypedMetatransaction(MetaTransaction metaTransaction) {
  return {
    'types': {
      'EIP712Domain': [
        {'name': 'name', 'type': 'string'},
        {'name': 'version', 'type': 'string'},
        {'name': 'chainId', 'type': 'uint256'},
        {'name': 'verifyingContract', 'type': 'address'},
      ],
      'MetaTransaction': [
        {'name': 'nonce', 'type': 'uint256'},
        {'name': 'from', 'type': 'address'},
        {'name': 'functionSignature', 'type': 'bytes'},
      ],
    },
    'domain': {
      'name': metaTransaction.name,
      'version': metaTransaction.version,
      //TODO: remove hardcoding
      'chainId': "80001",
      'verifyingContract': metaTransaction.verifyingContract,
      'salt': metaTransaction.salt,
    },
    'primaryType': 'MetaTransaction',
    'message': {
      'nonce': metaTransaction.nonce,
      'from': metaTransaction.from,
      'functionSignature': metaTransaction.functionSignature,
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
  final chainId = int.parse(config.gsn.chainId);
  String saltHexString = '0x${chainId.toRadixString(16)}';
  String paddedSaltHexString = saltHexString.padLeft(66, '0');
  printLog("paddedSaltHexString = $paddedSaltHexString");
  // typed data for signing
  final eip712Data = getTypedMetatransaction(
    MetaTransaction(
      name: contractName,
      version: '1',
      salt: paddedSaltHexString,
      // Padding the chainId with zeroes to make it 32 bytes
      verifyingContract: contractAddress,
      nonce: nonce,
      from: account.privateKey.address.hex,
      functionSignature: functionSignature,
    ),
  );
  // signature for metatransaction
  final String signature = EthSigUtil.signTypedData(
    jsonData: jsonEncode(eip712Data),
    version: TypedDataVersion.V4,
    privateKey: bytesToHex(account.privateKey.privateKey),
  );

  printLog("\n\nsignature from meta txn class = $signature\n\n");

  // get r,s,v from signature
  final signatureBytes = hexToBytes(signature);

  Map<String, dynamic> rsv = {
    'r': signatureBytes.sublist(0, 32),
    's': signatureBytes.sublist(32, 64),
    'v': signatureBytes[64],
  };
  printLog('r = ${rsv['r']}');
  printLog('s = ${rsv['s']}');
  printLog('v = ${rsv['v']}');

  return rsv;
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
    final decimalAmount =
        parseUnits(amount.toString(), int.parse(decimals.toString()));

    final data = token.function('transfer').encodeCall(
        [EthereumAddress.fromHex(destinationAddress), decimalAmount]);

    final signatureData = await getMetatransactionEIP712Signature(
      account,
      name,
      contractAddress,
      data,
      config,
      nonce.toInt(),
    );

    final executeMetaTransactionFunction =
        token.function('executeMetaTransaction');

    await provider.call(
        contract: token,
        function: executeMetaTransactionFunction,
        params: [
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

  final nameCallResult = await provider
      .call(contract: token, function: token.function('name'), params: []);
  final name = nameCallResult.first;

  final nonce =
      await getSenderContractNonce(provider, token, account.privateKey.address);
  final decimals = await provider
      .call(contract: token, function: token.function('decimals'), params: []);

  BigInt decimalAmount =
      parseUnits(amount.toString(), int.parse(decimals.first.toString()));

  // get function signature
  final transferFunc = token.function('transfer');
  final data = transferFunc
      .encodeCall([EthereumAddress.fromHex(destinationAddress), decimalAmount]);

  final signatureData = await getMetatransactionEIP712Signature(
    account,
    name,
    contractAddress,
    data,
    config,
    nonce.toInt(),
  );

  final r = signatureData['r'];
  final s = signatureData['s'];
  final v = signatureData['v'];

  final tx = Transaction.callContract(
    contract: token,
    function: token.function('executeMetaTransaction'),
    parameters: [
      account.privateKey.address,
      data,
      r,
      s,
      //TODO: is this correct?
      BigInt.from(v),
    ],
  );

  // Estimate the gas required for the transaction
  final gas = await provider.estimateGas(
    sender: account.privateKey.address,
    data: tx.data,
    to: EthereumAddress.fromHex(destinationAddress),
  );
  printLog("gas estimate: 0x${gas.toRadixString(16)}");

  final info = await provider.getBlockInformation();

  final BigInt maxPriorityFeePerGas = BigInt.parse("1500000000");
  final maxFeePerGas =
      info.baseFeePerGas!.getInWei * BigInt.from(2) + (maxPriorityFeePerGas);
  if (tx == null) {
    throw 'tx not populated';
  }

  final gsnTx = GsnTransactionDetails(
    from: account.privateKey.address.hex,
    data: bytesToHex(tx.data!),
    value: "0",
    to: tx.to!.hex,
    //TODO: Remove hardcoding
    gas: "0x${gas.toRadixString(16)}",
    maxFeePerGas: maxFeePerGas.toString(),
    maxPriorityFeePerGas: maxPriorityFeePerGas.toString(),
  );
  return gsnTx;
}
