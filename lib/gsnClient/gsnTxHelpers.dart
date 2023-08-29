import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart' as convertLib;
import 'package:convert/convert.dart';
import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter_sdk/contracts/tokenFaucet.dart';
import 'package:flutter_sdk/gsnClient/ABI/IForwarder.dart';
import 'package:flutter_sdk/utils/constants.dart';
import 'package:web3dart/crypto.dart';

import 'package:flutter_sdk/gsnClient/ABI/IRelayHub.dart';

import 'package:flutter_sdk/gsnClient/utils.dart';

import 'package:web3dart/web3dart.dart';

import '../network_config/network_config.dart';
import 'EIP712/ForwardRequest.dart';
import 'EIP712/RelayData.dart';
import 'EIP712/RelayRequest.dart';
import 'EIP712/typedSigning.dart';



  CalldataBytes calculateCalldataBytesZeroNonzero(Uint8List calldata) {
    final calldataBuf =
        calldata;
    int calldataZeroBytes = 0;
    int calldataNonzeroBytes = 0;

    calldataBuf.forEach((ch) {
      ch == 0 ? calldataZeroBytes++ : calldataNonzeroBytes++;
    });

    return CalldataBytes(calldataZeroBytes, calldataNonzeroBytes);
  }

  int calculateCalldataCost(
    Uint8List msgData,
    int gtxDataNonZero,
    int gtxDataZero,
  ) {
    var calldataBytesZeroNonzero = calculateCalldataBytesZeroNonzero(msgData);
    return (calldataBytesZeroNonzero.calldataZeroBytes * gtxDataZero +
        calldataBytesZeroNonzero.calldataNonzeroBytes * gtxDataNonZero);
  }

  String estimateGasWithoutCallData(
    GsnTransactionDetails transaction,
    int gtxDataNonZero,
    int gtxDataZero,
  ) {
    final originalGas = transaction.gas;
    final callDataCost = calculateCalldataCost(
      transaction.data,
      gtxDataNonZero,
      gtxDataZero,
    );
    final adjustedGas = BigInt.parse(originalGas!,radix: 16) - BigInt.from(callDataCost);

    return '0x${adjustedGas.toRadixString(16)}';
  }

  Future<String> estimateCalldataCostForRequest(
      RelayRequest relayRequestOriginal, GSNConfig config,Web3Client client) async {
    // Protecting the original object from temporary modifications done here
    var relayRequest = RelayRequest(
      request: ForwardRequest(
        from: relayRequestOriginal.request.from,
        to: relayRequestOriginal.request.to,
        value: relayRequestOriginal.request.value,
        gas: relayRequestOriginal.request.gas,
        nonce: relayRequestOriginal.request.nonce,
        data: relayRequestOriginal.request.data,
        validUntilTime: relayRequestOriginal.request.validUntilTime,
      ),
      relayData: RelayData(
        maxFeePerGas: relayRequestOriginal.relayData.maxFeePerGas,
        maxPriorityFeePerGas:
            relayRequestOriginal.relayData.maxPriorityFeePerGas,
        transactionCalldataGasUsed: '0xffffffffff',
        relayWorker: relayRequestOriginal.relayData.relayWorker,
        paymaster: relayRequestOriginal.relayData.paymaster,
        paymasterData:
            '0x${List.filled(config.maxPaymasterDataLength, 'ff').join()}',
        clientId: relayRequestOriginal.relayData.clientId,
        forwarder: relayRequestOriginal.relayData.forwarder,
      ),
    );

    const maxAcceptanceBudget = "0xffffffffff";
    // final maxAcceptanceBudget = BigInt.from(12345);
    final signature = '0x${List.filled(65, 'ff').join()}';
    final approvalData =
        '0x${List.filled(config.maxApprovalDataLength, 'ff').join()}';

    final relayHub = relayHubContract(config.relayHubAddress);
    // Estimate the gas cost for the relayCall function call

    var relayRequestJson = relayRequest.toJson();

    final function = relayHub.function('relayCall');
    printLog("BigInt.parse(maxAcceptanceBudget.substring(2), radix: 16), = ${BigInt.parse(maxAcceptanceBudget.substring(2), radix: 16)}");
    // Transaction.callContract(contract: contract, function: function, parameters: parameters)
    final tx = Transaction.callContract(contract: relayHub, function: function, parameters: [
      config.domainSeparatorName,
      BigInt.parse(maxAcceptanceBudget.substring(2), radix: 16),
      relayRequestJson,
      hexToBytes(signature),
      hexToBytes(approvalData)
    ]);
    // final tx = await client.call(contract: relayHub, function: function,
    //     params: [
    //       config.domainSeparatorName,
    //       BigInt.parse(maxAcceptanceBudget.substring(2), radix: 16),
    //       relayRequestJson,
    //       hexToBytes(signature),
    //       hexToBytes(approvalData)
    //     ]);

    if (tx == null) {
      throw 'tx not populated';
    }

    //todo: is the calculation of call data cost(from the rly sdk gsnTxHelper file)
    //similar to the estimate gas here?
    //TODO: remove this to string from next line
    return BigInt.from(calculateCalldataCost(tx.data!, config.gtxDataNonZero, config.gtxDataZero)).toRadixString(16);
  }

  Future<String> getSenderNonce(EthereumAddress sender,
      EthereumAddress forwarderAddress, Web3Client client) async {
    final forwarder = iForwarderContract(forwarderAddress);

    final List<dynamic> result = await client.call(
      contract: forwarder,
      function: forwarder.function("getNonce"),
      params: [sender],
    );
    // Extract the nonce value from the result and convert it to a string
    // if you go to getNonce method of IForwarderData.dart
    //there is only one output defined in the getNonce method
    //that's why we can be sure that result[0] will be used here
    final nonce = result.first.toString();
    return nonce;
  }

  Future<String> signRequest(
    RelayRequest relayRequest,
    String domainSeparatorName,
    String chainId,
    Wallet account,
  ) async {
    final cloneRequest = {
      "request": ForwardRequest(
        from: relayRequest.request.from,
        to: relayRequest.request.to,
        value: relayRequest.request.value,
        gas: relayRequest.request.gas,
        nonce: relayRequest.request.nonce,
        data: relayRequest.request.data,
        validUntilTime: relayRequest.request.validUntilTime,
      ).toMap(),
      "relayData": RelayData(
        maxFeePerGas: relayRequest.relayData.maxFeePerGas,
        maxPriorityFeePerGas: relayRequest.relayData.maxPriorityFeePerGas,
        transactionCalldataGasUsed:
        relayRequest.relayData.transactionCalldataGasUsed,
        relayWorker: relayRequest.relayData.relayWorker,
        paymaster: relayRequest.relayData.paymaster,
        paymasterData: relayRequest.relayData.paymasterData,
        clientId: relayRequest.relayData.clientId,
        forwarder: relayRequest.relayData.forwarder,
      ).toMap(),
    };
    //     String name, int chainId, EthereumAddress verifier, dynamic relayRequest)
    final signedGsnData = TypedGsnRequestData(
      domainSeparatorName,
      int.parse(chainId),
      relayRequest.relayData.forwarder,
      cloneRequest,
    );

    final signature = EthSigUtil.signTypedData(
      jsonData: jsonEncode(signedGsnData.message),
      privateKey: account.privateKey.toString(),
      version: TypedDataVersion.V1,
    );

    return signature;
  }

  String getRelayRequestID(
    Map<String, dynamic> relayRequest,
    String signature,
  ) {
    final types = ['address', 'uint256', 'bytes'];
    final parameters = [
      relayRequest['request']['from'],
      relayRequest['request']['nonce'],
      signature
    ];

    final hash = keccak256(AbiUtil.rawEncode(types, parameters));
    final rawRelayRequestId = hex.encode(hash).padLeft(64, '0');
    const prefixSize = 8;
    final prefixedRelayRequestId = rawRelayRequestId.replaceFirst(
        RegExp('^.{$prefixSize}'), '0' * prefixSize);
    return '0x$prefixedRelayRequestId';
  }

  Future<GsnTransactionDetails> getClaimTx(
    Wallet account,
    NetworkConfig config,
    Web3Client client,
  ) async {
    final faucet = tokenFaucet(
      config,
      EthereumAddress.fromHex(config.contracts.tokenFaucet),
    );

    final tx = faucet.function('claim').encodeCall([]);
    final gas = await client.estimateGas(
      sender: account.privateKey.address,
      data: tx,
      to: faucet.address,
    );

    //TODO:-> following code is inspired from getFeeData method of
    //abstract-provider of ethers js library
    //test if it exactly replicates the functions of getFeeData

    BlockInformation blockInformation = await client.getBlockInformation();
    final BigInt maxPriorityFeePerGas = BigInt.parse("1500000000");
    BigInt? maxFeePerGas;
    if(blockInformation.baseFeePerGas != null){
      maxFeePerGas =
          blockInformation.baseFeePerGas!.getInWei * BigInt.from(2) + (maxPriorityFeePerGas);
    }


    Uint8List data = tx;
    printLog("transaction data = $data");
    final gsnTx = GsnTransactionDetails(
      from: account.privateKey.address.toString(),
      data: data,
      value: "0",
      to: faucet.address.hex,
      gas: gas.toRadixString(16),
      maxFeePerGas: maxFeePerGas!.toRadixString(16),
      maxPriorityFeePerGas: maxPriorityFeePerGas.toRadixString(16),
    );

    return gsnTx;
  }

  Future<String> getClientId() async {
    // Replace this line with the actual method to get the bundleId from the native module
    final bundleId = await getBundleIdFromNativeModule();
//TODO:
    final hexValue = EthereumAddress.fromHex(bundleId).hex;
    return BigInt.parse(hexValue, radix: 16).toString();
  }

  Future<String> getBundleIdFromNativeModule() {
    // TODO: Replace this with the actual method to get the bundleId from the native module
    // Example: MethodChannel or Platform channel to communicate with native code
    // For demonstration purposes, we'll use a dummy value
    return Future.value('com.savez.app');
  }

  Future<String> handleGsnResponse(
    dynamic res,
    Web3Client ethClient,
  ) async {
    if (res.data['error'] != null) {
      throw {
        'message': 'RelayError',
        'details': res.data['error'],
      };
    } else {
      final txHash = keccak256(res.data['signedTx']).toString();
      // Poll for the transaction receipt until it's confirmed
      TransactionReceipt? receipt;
      do {
        receipt = await ethClient.getTransactionReceipt(txHash);
        if (receipt == null) {
          await Future.delayed(Duration(seconds: 2)); // Wait for 2 seconds
        }
      } while (receipt == null);
      return txHash;
    }
  }

Future<BigInt> getSenderContractNonce(Web3Client provider,DeployedContract token, EthereumAddress address) async {
  try{
    final fn = token.function('nonces');
    final fnCall  = await provider.call(contract: token, function: fn, params: [address]);
    return fnCall[0];

  } on Exception {
    final fn = token.function('getNonce');
    final fnCall  = await provider.call(contract: token, function: fn, params: [address]);
    return fnCall[0];
  }
}

BigInt parseUnits(String value, int decimals) {
  BigInt base = BigInt.from(10).pow(decimals);
  List<String> parts = value.split('.');
  BigInt wholePart = BigInt.parse(parts[0]);
  BigInt fractionalPart = parts.length > 1
      ? BigInt.parse(parts[1].padRight(decimals, '0'))
      : BigInt.zero;

  return wholePart * base + fractionalPart;
}

class CalldataBytes {
  final int calldataZeroBytes;
  final int calldataNonzeroBytes;

  CalldataBytes(this.calldataZeroBytes, this.calldataNonzeroBytes);
}
String uint8ListToHex(Uint8List list) {
  return '0x${hex.encode(list)}';
}