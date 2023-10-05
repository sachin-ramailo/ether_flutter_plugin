// PolygonNetworkConfig

import 'network_config.dart';

final polygonNetworkConfig = NetworkConfig(
  contracts: Contracts(
    tokenFaucet: '0x78a0794Bb3BB06238ed5f8D926419bD8fc9546d8',
    rlyERC20: '0xe537c642ac8c3136eb8914a047ab3b232f9e695d',
  ),
  gsn: GSNConfig(
    paymasterAddress: '0x61B9BdF9c10F77bD9eD033559Cec410427aeb8A2',
    forwarderAddress: '0xB2b5841DBeF766d4b521221732F9B618fCf34A87',
    relayHubAddress: '0xfCEE9036EDc85cD5c12A9De6b267c4672Eb4bA1B',
    relayWorkerAddress: '0x434efbca662f6f846f8dec3fde52fac4c8792e03',
    relayUrl: 'https://api.rallyprotocol.com',
    rpcUrl:
        'https://polygon-mainnet.g.alchemy.com/v2/-dYNjZXvre3GC9kYtwDzzX4N8tcgomU4',
    chainId: '137',
    maxAcceptanceBudget: '285252',
    domainSeparatorName: 'GSN Relayed Transaction',
    gtxDataNonZero: 16,
    gtxDataZero: 4,
    requestValidSeconds: 172800,
    maxPaymasterDataLength: 300,
    maxApprovalDataLength: 0,
    maxRelayNonceGap: 3,
  ),
);
