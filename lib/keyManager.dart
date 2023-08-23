import 'dart:ffi';

import 'package:convert/convert.dart';
import 'package:ed25519_hd_key/ed25519_hd_key.dart';
import 'package:flutter/services.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_sdk/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keyStorageConfig.dart';

abstract class KeyManager {
  Future<String?> getMnemonic();
  Future<String?> generateMnemonic();
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
  Future<String?> generateMnemonic() async {
    String? mnemonic = await methodChannel.invokeMethod<String>("generateNewMnemonic");
    printLog("get mnemonic = $mnemonic");
    saveMnemonic(mnemonic!);
    return mnemonic;
  }

  @override
  Future<String?> getMnemonic() async {

    String? mnemonic = await methodChannel.invokeMethod<String>("getMnemonic");
    printLog("get mnemonic = $mnemonic");

    //TODO: ultimately this has to be done from native code
    printLog("mnemonic = $mnemonic");
    if (isStringEmpty(mnemonic)) {
      mnemonic = await generateMnemonic();
    }
    printLog("mnemonic = $mnemonic");
    return mnemonic;
  }

  @override
  Future<String> makePrivateKeyFromMnemonic(String mnemonic) async {
    //TODO: ultimately this has to be done from native code
    List<Object?>? pvtKey = await methodChannel.invokeMethod<List<Object?>>("getPrivateKeyFromMnemonic",{
      'mnemonic':mnemonic,
    });
    String strPvtKey = uint8ListToHex(pvtKey!);
    printLog('pvtKey = ${strPvtKey!}');
    return strPvtKey;
  }

  String uint8ListToHex(List<Object?> uint8List) {
    Uint8List list = Uint8List.fromList([]);
    List<int> list1 = [];
    for(Object? obj in uint8List){
      list1.add(int.parse(obj.toString()));
    }
    // Convert the Uint8List to a string of bytes.
    String bytesString = list1.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
    // Return the string of bytes as a hex string.
    return '0x$bytesString';
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
