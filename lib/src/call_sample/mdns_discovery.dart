// import 'dart:convert';
// import 'dart:io';
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter_mdns_plugin/flutter_mdns_plugin.dart';
// import 'package:http/http.dart' as http;
// import 'package:dio/dio.dart';

// class MdnsDiscovery extends StatefulWidget {
//   final String apppath;
//   final String peerId;
//   MdnsDiscovery({required this.apppath, required this.peerId});

//   @override
//   _MdnsDiscoveryState createState() => _MdnsDiscoveryState();
// }

// const String discoveryService = "_webrtc-webcam._tcp";

// class _MdnsDiscoveryState extends State<MdnsDiscovery> {
//   Timer? _timer;
//   bool _recvdiscoveryed = false;
//   FlutterMdnsPlugin? _mdnsPlugin;
//   List<String> messageLog = <String>[];
//   late DiscoveryCallbacks discoveryCallbacks;

//   @override
//   initState() {
//     super.initState();

//     discoveryCallbacks = new DiscoveryCallbacks(
//       onDiscovered: (ServiceInfo info) {
//         // print("Discovered  ${info.toString()}");
//       },
//       onDiscoveryStarted: () {
//         //  print("Discovery started");
//       },
//       onDiscoveryStopped: () {
//         //  print("Discovery stopped");
//       },
//       onResolved: (ServiceInfo info) {
//         print("Discovery Resolved Service ${info.toString()}");
//         if (_recvdiscoveryed == false) {
//           _recvdiscoveryed = true;
//           String address = info.address;
//           int port = info.port;
//           String url =
//               "http://" + address + ":" + port.toString() + "/api/wifi/config";
//           doJsonPostConfigwifi(url);
//           //postJsonClient(url);
//         }
//       },
//     );
//     _mdnsPlugin = FlutterMdnsPlugin(discoveryCallbacks: discoveryCallbacks);
//     // messageLog.add("Starting mDNS for service [$discovery_service]");
//     startMdnsDiscovery(discoveryService);
//     _startTimer();
//   }

//   void _startTimer() {
//     const oneSec = Duration(seconds: 5);
//     _timer = Timer.periodic(oneSec, (Timer timer) {});
//   }

//   Future<void> stopDiscovery() async {
//     await _mdnsPlugin?.stopDiscovery();
//   }

//   Future<void> startMdnsDiscovery(String serviceType) async {
//     await _mdnsPlugin?.startDiscovery(serviceType);
//   }

//   void disableLocalTrustedCertificates(Dio dio) {
//     // 在调试模式下禁用本地信任的证书
//     /*
//     (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate = (client) {
//       client.badCertificateCallback = (X509Certificate cert, String host, int port) {
//         // 返回true来允许所有证书，这将禁用本地证书检查
//         return true;
//       };
//     };
//     */
//   }

//   Future<void> postJsonClient(String url) async {
//     var client = http.Client();
//     Map<String, String> headersMap = new Map();
//     headersMap["content-type"] = ContentType.json.toString();
//     Map<String, String> bodyParams = new Map();
//     bodyParams['key'] = "0fdafdsafdafdfdsafdsafdsaf";
//     bodyParams['ssid'] = "runhua";
//     bodyParams['pwd'] = "01234567890";
//     bodyParams['ip'] = "apicn.newaylink.com";
//     client
//         .post(
//           Uri.parse(url),
//           headers: headersMap,
//           body: jsonEncode(bodyParams),
//           encoding: Utf8Codec(),
//         )
//         .then((http.Response response) {
//           if (response.statusCode == 200) {
//             print('请求成功');
//             print(response.body);
//           } else {
//             print('error');
//           }
//         })
//         .catchError((error) {
//           print('error');
//         });
//   }

//   Future<void> doJsonPostConfigwifi(String url) async {
//     try {
//       var data = {
//         'key': '0fdafdsafdafdfdsafdsafdsaf',
//         'ssid': '8A',
//         'pwd': 'Yibao520',
//         'ip': 'apicn.newaylink.com',
//       };

//       var body = json.encode(data);
//       print("doJsonPostConfigwifi  $url  $body");

//       final response = await http.post(
//         Uri.parse(url),
//         headers: {'Content-Type': 'application/json'},
//         body: body,
//       );

//       if (response.statusCode == 200) {
//         // 请求成功
//         print('请求成功');
//         print(response.body);
//       } else {
//         // 请求失败
//         print('请求失败');
//         print(response.statusCode);
//       }
//     } catch (e) {
//       // 处理异常
//       print('Caught exception: $e');
//     }

//     /*
//     var uri = Uri.parse(url);
//     var params = {
//       "key": "8989-dddvdg",
//       "ssid": "文章标题-JSON格式参数演示",
//       "pwd": "快速入门json参数",
//       "ip": "分类"
//     };
//     var json = jsonEncode(params);
//     print("doJsonPostConfigwifi  $url  $json");
//     var response = await http.post(uri, body: json, headers: {
//       'content-type': 'application/json'
//     }); //设置content-type为application/json
//     if (response.statusCode == 200) {
//       //请求成功
//       _success(response, false);
//     } else {
//       //请求失败
//       _failed(response);
//     }
//     */
//   }

//   IconButton _button() {
//     return IconButton(
//       icon: Icon(Icons.favorite),
//       onPressed: () {
//         print("点击了 button");
//       },
//       color: Colors.blue,
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return WillPopScope(
//       child: Scaffold(
//         appBar: AppBar(title: Text('Mdns Discovery')),
//         body: Center(
//           child: IconButton(
//             icon: Icon(Icons.favorite),
//             // 在这里处理按钮点击事件
//             onPressed: () {
//               print('IconButton pressed!');
//               //doJsonPostConfigwifi("http://192.168.1.110/api/wifi/config");
//             },
//             color: Colors.red,
//             iconSize: 88,
//             tooltip: 'Add to favorites',
//           ),
//         ),

//         /*
//         body: new ListView.builder(
//         reverse: true,
//         itemCount: messageLog.length,
//         itemBuilder: (BuildContext context, int index) {
//           return new Text(messageLog[index]);
//         },
//       ),
//       */
//       ),
//       onWillPop: () {
//         //监听到退出按键
//         return Future<bool>.value(true);
//       },
//     );
//   }

//   @override
//   void dispose() {
//     stopDiscovery();
//     _timer?.cancel();
//     super.dispose();
//   }
// }
