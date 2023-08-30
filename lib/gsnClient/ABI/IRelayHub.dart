import 'dart:convert';

import 'package:flutter_sdk/gsnClient/ABI/IRelayHubData.dart';
import 'package:web3dart/web3dart.dart';

DeployedContract relayHubContract(String contractAddress) {
  return DeployedContract(
    ContractAbi.fromJson(jsonEncode(getIRelayHubData()),'IRelayHub'),
    EthereumAddress.fromHex(contractAddress),
  );
}
