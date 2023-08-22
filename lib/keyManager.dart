import 'package:convert/convert.dart';
import 'package:ed25519_hd_key/ed25519_hd_key.dart';
import 'package:flutter/services.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_sdk/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keyStorageConfig.dart';

abstract class KeyManager {
  Future<String?> getMnemonic();
  String generateMnemonic();
  void saveMnemonic(String mnemonic, {KeyStorageConfig? options});
  void deleteMnemonic();
  Future<String> makePrivateKeyFromMnemonic(String mnemonic);
  Future<String> getStoredPrivateKey();
}

class KeychainAccessibilityConstant {
  final int value;

  const KeychainAccessibilityConstant(this.value);
}

const AFTER_FIRST_UNLOCK = KeychainAccessibilityConstant(0);
const AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY = KeychainAccessibilityConstant(1);
const ALWAYS = KeychainAccessibilityConstant(2);
const WHEN_PASSCODE_SET_THIS_DEVICE_ONLY = KeychainAccessibilityConstant(3);
const ALWAYS_THIS_DEVICE_ONLY = KeychainAccessibilityConstant(4);
const WHEN_UNLOCKED = KeychainAccessibilityConstant(5);
const WHEN_UNLOCKED_THIS_DEVICE_ONLY = KeychainAccessibilityConstant(6);

class KeyManagerImpl extends KeyManager {
  final methodChannel = const MethodChannel('flutter_sdk');

  @override
  void deleteMnemonic() {
    // TODO: implement deleteMnemonic
    throw UnimplementedError();
  }

  @override
  String generateMnemonic() {
    String mnemonic = bip39.generateMnemonic();

    saveMnemonic(mnemonic);
    return mnemonic;
  }

  @override
  Future<String?> getMnemonic() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    printLog('version  = $version');

    String? mnemonic = await methodChannel.invokeMethod<String>("readMnemonic",
        {
          "key": kkeyForStoringMnemonic,
        }
    );
    printLog("get mnemonic = $mnemonic");

    //TODO: ultimately this has to be done from native code
    printLog("mnemonic = $mnemonic");
    if (isStringEmpty(mnemonic)) {
      mnemonic = generateMnemonic();
    }
    printLog("mnemonic = $mnemonic");
    return mnemonic;
  }

  Future<String> mnemonicToPrivateKey(String mnemonic) async {
    //TODO: ultimately this has to be done from native code
    return bip39.mnemonicToSeedHex(mnemonic);
  }

  @override
  Future<String> makePrivateKeyFromMnemonic(String mnemonic) async {
    //TODO: ultimately this has to be done from native code
    if (isStringEmpty(mnemonic)) {
      throw Exception("mnemonic can not be empty!");
    }
    final seed = bip39.mnemonicToSeed(mnemonic);
    final master = await ED25519_HD_KEY.getMasterKeyFromSeed(seed);
    final privateKey = hex.encode(master.key);
    return privateKey;
  }

  @override
  Future<void> saveMnemonic(String mnemonic,
      {KeyStorageConfig? options}) async {
    if (options == null || !options.saveToCloud) {
      SharedPreferences preferences = await SharedPreferences.getInstance();
      preferences.setString(kkeyForStoringMnemonic, mnemonic);
      // TODO: don't pass false false
      await methodChannel.invokeMethod("saveMnemonic",{
        "key": kkeyForStoringMnemonic,
        "mnemonic": mnemonic,
        "useBlockstore": false,
        "forceBlockstore": false,
      });
    }
  }

  @override
  Future<String> getStoredPrivateKey() async {
    String? mnemonic = await getMnemonic();
    return await makePrivateKeyFromMnemonic(mnemonic!);
  }
}
