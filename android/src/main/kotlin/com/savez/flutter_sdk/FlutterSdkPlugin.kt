package com.savez.flutter_sdk

import android.content.Context
import androidx.annotation.NonNull
import androidx.security.crypto.MasterKey
import com.rlynetworkmobilesdk.EncryptedSharedPreferencesHelper
import org.kethereum.bip39.generateMnemonic
import org.kethereum.bip39.validate
import org.kethereum.bip39.dirtyPhraseToMnemonicWords
import org.kethereum.bip39.toSeed
import org.kethereum.bip39.wordlists.WORDLIST_ENGLISH
import org.kethereum.bip39.model.MnemonicWords
import org.kethereum.bip32.model.ExtendedKey
import org.kethereum.bip32.toKey
import org.kethereum.extensions.*
import java.lang.Integer.parseInt

import com.rlynetworkmobilesdk.MnemonicStorageHelper

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** FlutterSdkPlugin */
const val MNEMONIC_STORAGE_KEY = "BIP39_MNEMONIC"
class FlutterSdkPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var prefHelper: EncryptedSharedPreferencesHelper
  private val MNEMONIC_PREFERENCE_KEY = "BIP39_MNEMONIC"

  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel: MethodChannel
  private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_sdk")
    channel.setMethodCallHandler(this)
    this.flutterPluginBinding = flutterPluginBinding
    prefHelper = EncryptedSharedPreferencesHelper(flutterPluginBinding.applicationContext)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {

    if (call.method == "getPlatformVersion") {
      result.success("Android ${android.os.Build.VERSION.RELEASE}")
    }
    if (call.method == "saveMnemonic") {
      saveMnemonic(call, result);
    } else if (call.method == "readMnemonic") {
      readMnemonic(call, result)
    } else if (call.method == "deleteMnemonic") {
      deleteMnemonic(call, result)
    } else if (call.method == "generateMnemonic") {
      val phrase = generateMnemonic(192, WORDLIST_ENGLISH)
      result.success(phrase)
    } else {
      result.notImplemented()
    }
  }

  private fun deleteMnemonic(call: MethodCall, result: Result) {
    val key = call.argument<String?>("key") ?: "null"
    val mnemonicStorageHelper = MnemonicStorageHelper(flutterPluginBinding.applicationContext)
    mnemonicStorageHelper.delete(key);
  }

  private fun readMnemonic(call: MethodCall, result: Result) {
    val mnemonicStorageHelper = MnemonicStorageHelper(flutterPluginBinding.applicationContext)
    mnemonicStorageHelper.read(MNEMONIC_STORAGE_KEY, onSuccess = { value ->
      result.success(value)
    })
  }

  private fun saveMnemonic(call: MethodCall, result: Result) {
    call.argument<String?>("mnemonic")?.let { mnemonic ->
      if (!MnemonicWords(mnemonic).validate(WORDLIST_ENGLISH)) {
        result.error("mnemonic_verification_failure", "Mnemonic is not valid", null)
      }
      prefHelper.save(MNEMONIC_PREFERENCE_KEY, mnemonic)
      result.success(true)
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
