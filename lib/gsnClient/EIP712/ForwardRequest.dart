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
  Map<String,dynamic> toMap(){
    return {
      'from': from,
      'to': to,
      'value': value,
      'gas': gas,
      'nonce': nonce,
      'data': data,
      'validUntilTime': validUntilTime
    };
  }

}
