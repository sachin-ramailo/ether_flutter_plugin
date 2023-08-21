import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_sdk/gsnClient/EIP712/ForwardRequest.dart';
import 'package:flutter_sdk/gsnClient/EIP712/RelayData.dart';
import 'package:flutter_sdk/gsnClient/utils.dart';
import 'package:flutter_sdk/utils/constants.dart';
import 'package:web3dart/web3dart.dart';
import 'package:flutter_sdk/gsnClient/gsnTxHelpers.dart';

import '../network_config/network_config.dart';
import 'EIP712/RelayRequest.dart';


Future<Map<String, dynamic>> updateConfig(
  NetworkConfig config,
  GsnTransactionDetails transaction,
) async {
  final response = await http.get(Uri.parse('${config.gsn.relayUrl}/getaddr'));
  final data = json.decode(response.body);

  config.gsn.relayWorkerAddress = data['relayWorkerAddress'];
  transaction.maxPriorityFeePerGas = data['minMaxPriorityFeePerGas'];

  transaction.maxFeePerGas = config.gsn.chainId == 80001
      ? data['minMaxPriorityFeePerGas']
      : data['maxMaxFeePerGas'].toString();

  return {'config': config, 'transaction': transaction};
}

Future<RelayRequest> buildRelayRequest(
  GsnTransactionDetails transaction,
  NetworkConfig config,
  Wallet account,
    Web3Client  web3Provider,
) async {
  transaction.gas = estimateGasWithoutCallData(
    transaction,
    config.gsn.gtxDataNonZero,
    config.gsn.gtxDataZero,
  );

  final secondsNow = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final validUntilTime =
      (secondsNow + config.gsn.requestValidSeconds).toString();

  final senderNonce = await getSenderNonce(
    account.privateKey.address,
    EthereumAddress.fromHex(
    config.gsn.forwarderAddress),
    web3Provider,
  );
ForwardRequest forwardRequest = ForwardRequest(from: transaction.from, to: transaction.to,
    value: transaction.value ?? '0', gas: int.parse(transaction.gas!, radix: 16).toString(), nonce: senderNonce,
    data: transaction.data, validUntilTime: validUntilTime,);
  RelayData relayData = RelayData(maxFeePerGas: transaction.maxFeePerGas, maxPriorityFeePerGas: transaction.maxPriorityFeePerGas,
      transactionCalldataGasUsed: '',
      relayWorker: config.gsn.relayWorkerAddress, paymaster: config.gsn.relayWorkerAddress,
      paymasterData: config.gsn.paymasterAddress, clientId: '1', forwarder: config.gsn.forwarderAddress);
RelayRequest relayRequest = RelayRequest(request: forwardRequest, relayData: relayData);

  final transactionCalldataGasUsed =
      await estimateCalldataCostForRequest(relayRequest, config.gsn);

  relayRequest.relayData.transactionCalldataGasUsed =
      int.parse(transactionCalldataGasUsed, radix: 16).toString();

  return relayRequest;
}

Future<Map<String, dynamic>> buildRelayHttpRequest(
  RelayRequest relayRequest,
  NetworkConfig config,
  Wallet account,
  Web3Client web3Provider,
) async {
  final signature = await signRequest(
    relayRequest,
    config.gsn.domainSeparatorName,
    config.gsn.chainId,
    account,
  );

  const approvalData = '0x';


  final relayWorkerAddress = EthereumAddress.fromHex(relayRequest.relayData.relayWorker);
  final relayLastKnownNonce = await web3Provider.getTransactionCount(relayWorkerAddress);
  final relayMaxNonce = relayLastKnownNonce + config.gsn.maxRelayNonceGap;

  final metadata = {
    'maxAcceptanceBudget': config.gsn.maxAcceptanceBudget,
    'relayHubAddress': config.gsn.relayHubAddress,
    'signature': signature,
    'approvalData': approvalData,
    'relayMaxNonce': relayMaxNonce,
    'relayLastKnownNonce': relayLastKnownNonce,
    'domainSeparatorName': config.gsn.domainSeparatorName,
    'relayRequestId': '',
  };
  final httpRequest = {
    'relayRequest': relayRequest,
    'metadata': metadata,
  };

  return httpRequest;
}

Future<String> relayTransaction(
  Wallet account,
  NetworkConfig config,
  GsnTransactionDetails transaction,
) async {
getEthClient();
  final web3Provider = getEthClientForURL(config.gsn.rpcUrl);
  final updatedConfig = await updateConfig(config, transaction);
  final relayRequest = await buildRelayRequest(
    updatedConfig['transaction'],
    updatedConfig['config'],
    account,
    web3Provider,
  );
  final httpRequest = await buildRelayHttpRequest(
    relayRequest,
    updatedConfig['config'],
    account,
    web3Provider,
  );

  final relayRequestId = getRelayRequestID(
    httpRequest['relayRequest'],
    httpRequest['metadata']['signature'],
  );

  // Update request metadata with relayrequestid
  httpRequest['metadata']['relayRequestId'] = relayRequestId;

  final authHeader = {
    'Authorization': 'Bearer ${config.relayerApiKey ?? ''}',
  };

  final res = await http.post(
    Uri.parse('${config.gsn.relayUrl}/relay'),
    headers: authHeader,
    body: json.encode(httpRequest),
  );
  return handleGsnResponse(res, web3Provider);
}
