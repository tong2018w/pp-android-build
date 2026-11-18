import 'dart:async' show Timer;
import 'dart:convert' show jsonDecode;
import 'dart:io' show Platform;

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/main.dart';
import 'package:PiliPlus/pages/login/controller.dart';
import 'package:PiliPlus/plugin/linux_webview.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class GeetestWebviewDialog extends StatefulWidget {
  const GeetestWebviewDialog(this.gt, this.challenge, {super.key});

  final String gt;
  final String challenge;

  @override
  State<GeetestWebviewDialog> createState() => _GeetestWebviewDialogState();

  static Future<Map<String, dynamic>?> geetest(String gt, String challenge) {
    return showDialog<Map<String, dynamic>>(
      context: Get.context!,
      builder: (context) => GeetestWebviewDialog(gt, challenge),
    );
  }
}

class _GeetestWebviewDialogState extends State<GeetestWebviewDialog> {
  static const _geetestJsUri =
      'https://static.geetest.com/static/js/fullpage.0.0.0.js';
  static const _geetestConfigUri = 'https://api.geetest.com/gettype.php';

  /// 极验要求页面有真实的 https 源，否则拿不到域名/存储，只出白屏
  static const _geetestHost = 'https://www.bilibili.com/';

  /// 加载超时时间：宁可提示重试，也不要让用户干瞪着空白页
  static const _loadTimeout = Duration(seconds: 15);

  /// 极验对老 UA 会拒发完整校验脚本，用一个较新的 Android Chrome UA
  static const _captchaUa =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  Timer? _timer;

  /// 已经拿到结果或已关闭，超时就不再打扰
  bool _finished = false;

  /// 加载失败的提示文案，null 表示正常加载中
  String? _error;

  /// 重试计数，用来重建 WebView
  int _attempt = 0;

  static String _buildHtml(String gt, String challenge) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final js =
        'var C,S,T,t;'
        'T=()=>{if(C&&S&&!t){'
        'var l=document.getElementById("L");if(l){l.style.display="none"}'
        't=Geetest(C).onSuccess(()=>R("success",t.getValidate())).onError(o=>R("error",o)).onClose(o=>R("close",o));'
        't.onReady(()=>t.verify())}};'
        'geetest_$ts=(d)=>{'
        'if(!d||d.status!="success"){R("error",JSON.stringify(d));return};'
        'C=Object.assign({gt:"$gt",challenge:"$challenge",offline:false,new_captcha:true,product:"bind",width:"100%",https:true,protocol:"https://"},d.data);T()'
        '};'
        'G=()=>{S=1;T()};'
        'E=(m)=>{var e=document.getElementById("E");if(e){e.textContent="验证码加载失败";e.style.display="flex"}'
        'var l=document.getElementById("L");if(l){l.style.display="none"}'
        'R("error",typeof m=="string"?m:"geetest script load failed")}';

    return '<!DOCTYPE html><html><head>'
        '<meta name="viewport" content="width=device-width">'
        '<meta name="color-scheme" content="light dark">'
        '</head>'
        '<style>'
        'html,body{margin:0;padding:0;background:transparent}'
        '#L{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;font:14px sans-serif;opacity:.6}'
        '#E{position:fixed;inset:0;display:none;align-items:center;justify-content:center;color:#f44336;font:14px sans-serif}'
        '</style>'
        '<body><div id="L">正在加载验证码…</div><div id="E"></div>'
        '<script>'
        '${Platform.isLinux ? "R=(n,o)=>window.PiliPlus.postMessage(n+':'+JSON.stringify(o))" : "R=(n,o)=>window.flutter_inappwebview?.callHandler(n,o)"};$js'
        '</script>'
        '<script src="$_geetestJsUri" onload="G()" onerror="E(\'极验脚本加载失败\')"></script>'
        '<script src="$_geetestConfigUri?gt=$gt&callback=geetest_$ts" onerror="E(\'极验配置请求失败\')"></script>'
        '</body></html>';
  }

  @override
  void initState() {
    super.initState();
    if (!Platform.isLinux) _armTimeout();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _armTimeout() {
    _timer?.cancel();
    if (_error != null) return;
    _timer = Timer(_loadTimeout, () {
      if (!mounted || _finished) return;
      setState(() => _error = '验证码加载超时。检查网络重试，或登录页切换到扫码登录');
    });
  }

  void _retry() {
    _timer?.cancel();
    setState(() {
      _error = null;
      _attempt++;
    });
    _armTimeout();
  }

  void _fail(String reason) {
    debugPrint('geetest error: $reason');
    if (!mounted || _finished || _error != null) return;
    _timer?.cancel();
    // 极验脚本自己会先显示失败文案，这里同步给 Dart 侧兜底
    setState(() => _error = '验证码加载失败。可重试，或登录页切换到扫码登录');
  }

  @override
  Widget build(BuildContext context) {
    final html = _buildHtml(widget.gt, widget.challenge);

    if (Platform.isLinux) {
      return AlertDialog(
        title: const Text('验证码'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: LinuxWebview(
            initialHtml: html,
            userAgent: _captchaUa,
            incognito: false,
            onWebMessageReceived: (msg) {
              final msgStr = msg.toString();
              if (msgStr.startsWith("success:")) {
                final dataStr = msgStr.substring("success:".length);
                try {
                  final data = jsonDecode(dataStr);
                  Get.back(result: data);
                } catch (e) {
                  debugPrint('geetest decode error: $e');
                }
              } else if (msgStr.startsWith("error:")) {
                debugPrint('geetest error: $msgStr');
              } else if (msgStr.startsWith('close:')) {
                Get.back();
              }
            },
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Stack(
      children: [
        InAppWebView(
          key: ValueKey(_attempt),
          webViewEnvironment: webViewEnvironment,
          initialSettings: InAppWebViewSettings(
            clearCache: false,
            javaScriptEnabled: true,
            // 强制暗色会把极验的白底页面反色成一片空白，必须关掉
            forceDark: ForceDark.OFF,
            useHybridComposition: true,
            algorithmicDarkeningAllowed: false,
            useShouldOverrideUrlLoading: true,
            userAgent: _captchaUa,
            mixedContentMode: .MIXED_CONTENT_ALWAYS_ALLOW,

            // incognito 会禁掉 cookie，极验靠 cookie 校验域名与会话，
            // 开着它极验脚本能加载但校验一定失败 → 白屏/失败提示
            incognito: false,
            allowFileAccess: false,
            allowsLinkPreview: false,
            allowContentAccess: false,
            useOnDownloadStart: false,
            geolocationEnabled: false,
            // 极验脚本要写 localStorage / cookie 才能渲染出滑块
            domStorageEnabled: true,
            databaseEnabled: true,
            thirdPartyCookiesEnabled: true,
            enterpriseAuthenticationAppLinkPolicyEnabled: false,
            saveFormData: false,
            safeBrowsingEnabled: false,
            isFraudulentWebsiteWarningEnabled: false,
            cacheEnabled: true,
            cacheMode: .LOAD_DEFAULT,

            horizontalScrollBarEnabled: false,
            verticalScrollBarEnabled: false,
            overScrollMode: .NEVER,

            pageZoom: Platform.isIOS ? 3 : 1,
          ),
          initialData: InAppWebViewInitialData(
            data: html,
            baseUrl: WebUri(_geetestHost),
          ),
          onWebViewCreated: (ctr) {
            ctr
              ..addJavaScriptHandler(
                handlerName: 'success',
                callback: (args) {
                  if (args.isNotEmpty) {
                    if (args[0] case Map<String, dynamic> data) {
                      _finished = true;
                      _timer?.cancel();
                      Get.back(result: data);
                      return;
                    }
                  }
                  _fail('invalid result: $args');
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'error',
                callback: (args) {
                  _fail(args.isEmpty ? 'unknown' : '${args[0]}');
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'close',
                callback: (args) {
                  _finished = true;
                  _timer?.cancel();
                  Get.back();
                },
              );
          },
        ),
        if (_error != null)
          Positioned.fill(
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: .min,
                    spacing: 12,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 32,
                        color: theme.colorScheme.error,
                      ),
                      Text(
                        _error!,
                        textAlign: .center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      FilledButton.tonal(
                        onPressed: _retry,
                        child: const Text('重试'),
                      ),
                      TextButton(
                        onPressed: () {
                          Get.back();
                          // 极验在本机/本网络加载失败时，一键切到「扫码」Tab
                          // （登录页 Tab 顺序：0 密码 / 1 短信 / 2 扫码 / 3 Cookie）
                          try {
                            Get.find<LoginPageController>()
                                .tabController
                                .animateTo(2);
                          } catch (_) {}
                        },
                        child: const Text('关闭，改用扫码登录'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 8,
          top: 8,
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              _finished = true;
              _timer?.cancel();
              Get.back();
            },
            tooltip: '关闭',
          ),
        ),
      ],
    );
  }
}
