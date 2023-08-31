import 'package:eth_sig_util/model/typed_data.dart';

import '../utils.dart';

class MessageTypeProperty {
  String name;
  String type;

  MessageTypeProperty({required this.name, required this.type});
}

class TypedGsnRequestData {
  late GsnPrimaryType types;
  late EIP712Domain domain;
  late String primaryType;
  late dynamic message;

  TypedGsnRequestData(
      String name, int chainId, Address verifier, Map<String, dynamic> relayRequest) {
    types = GsnPrimaryType(relayData:RelayDataType,
        relayRequest: RelayRequestType);
    domain = getDomainSeparator(name, verifier, chainId);
    primaryType = 'RelayRequest';
    // In the signature, all "request" fields are flattened out at the top structure.
    // Other params are inside "relayData" sub-type.
    message = {
      ...relayRequest['request'],
      /*
      "from": relayRequest['request']['from'],
      "to": relayRequest['request']['to'],
      ....
       */
      'relayData': relayRequest['relayData'],
    };
  }
}

Map<String, dynamic> GsnDomainSeparatorType = {
  'prefix': 'string name,string version',
  'version': '3',
};

EIP712Domain getDomainSeparator(String name, Address verifier, int chainId) {
  return EIP712Domain(
    chainId: chainId,
    name: name,
    version: GsnDomainSeparatorType['version'],
    verifyingContract: verifier,
  );
}

List<MessageTypeProperty> EIP712DomainType = [
  MessageTypeProperty(name: 'name', type: 'string'),
  MessageTypeProperty(name: 'version', type: 'string'),
  MessageTypeProperty(name: 'chainId', type: 'uint256'),
  MessageTypeProperty(name: 'verifyingContract', type: 'address'),
];

List<MessageTypeProperty> EIP712DomainTypeWithoutVersion = [
  MessageTypeProperty(name: 'name', type: 'string'),
  MessageTypeProperty(name: 'chainId', type: 'uint256'),
  MessageTypeProperty(name: 'verifyingContract', type: 'address'),
];

List<MessageTypeProperty> RelayDataType = [
  MessageTypeProperty(name: 'maxFeePerGas', type: 'uint256'),
  MessageTypeProperty(name: 'maxPriorityFeePerGas', type: 'uint256'),
  MessageTypeProperty(name: 'transactionCalldataGasUsed', type: 'uint256'),
  MessageTypeProperty(name: 'relayWorker', type: 'address'),
  MessageTypeProperty(name: 'paymaster', type: 'address'),
  MessageTypeProperty(name: 'forwarder', type: 'address'),
  MessageTypeProperty(name: 'paymasterData', type: 'bytes'),
  MessageTypeProperty(name: 'clientId', type: 'uint256'),
];

List<MessageTypeProperty> ForwardRequestType = [
  MessageTypeProperty(name: 'from', type: 'address'),
  MessageTypeProperty(name: 'to', type: 'address'),
  MessageTypeProperty(name: 'value', type: 'uint256'),
  MessageTypeProperty(name: 'gas', type: 'uint256'),
  MessageTypeProperty(name: 'nonce', type: 'uint256'),
  MessageTypeProperty(name: 'data', type: 'bytes'),
  MessageTypeProperty(name: 'validUntilTime', type: 'uint256'),
];

List<MessageTypeProperty> RelayRequestType = [
  ...ForwardRequestType,
  MessageTypeProperty(name: 'relayData', type: 'RelayData'),
];

class MessageTypes {
  List<MessageTypeProperty> EIP712Domain = EIP712DomainType;
  Map<String, MessageTypeProperty> additionalProperties = {};
}

class GsnPrimaryType {
  List<MessageTypeProperty> relayRequest;
  List<MessageTypeProperty> relayData;

  GsnPrimaryType({
    required this.relayRequest,
    required this.relayData,
  });

}

class EIP712Domain {
  final String? name;
  final String? version;
  final int? chainId;
  final String? verifyingContract;

  EIP712Domain({
    required this.name,
    required this.version,
    required this.chainId,
    required this.verifyingContract
  });
}
