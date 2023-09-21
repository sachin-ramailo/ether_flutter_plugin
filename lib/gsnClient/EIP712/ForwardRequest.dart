import 'dart:typed_data';

import 'package:eth_sig_util/util/utils.dart';
import 'package:web3dart/credentials.dart';

import '../utils.dart';

class ForwardRequest {
  Address from;
  Address to;
  IntString value;
  IntString gas;
  IntString nonce;
  String data;
  IntString validUntilTime;

  ForwardRequest({
    required this.from,
    required this.to,
    required this.value,
    required this.gas,
    required this.nonce,
    required this.data,
    required this.validUntilTime,
  });
  List<dynamic> toJson() {
    return [
      EthereumAddress.fromHex(from),
      EthereumAddress.fromHex(to),
      BigInt.parse(value),
      BigInt.parse(gas),
      BigInt.parse(nonce),
      hexToBytes(data),
      BigInt.parse(validUntilTime)
    ];
  }

  Map<String, dynamic> toMap() {
    return {
      // 'from': "0x765B2b2070ca0904490F72838ef5D6ca8cA70D39",
      'from': from,
      'to': "0x5205BcC1852c4b626099aa7A2AFf36Ac3e9dE83b",
      'value': value,
      'gas': gas,
      'nonce': nonce,
      'data': data,
      'validUntilTime': validUntilTime
    };
  }
}
