import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapPickerPage extends StatefulWidget {
  /// 接收初始座標
  final LatLng? initialPosition;
  const MapPickerPage({Key? key, this.initialPosition}) : super(key: key);

  @override
  _MapPickerPageState createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  late GoogleMapController _mapController;

  /// 地圖中心與標記位置
  late LatLng _currentPosition;
  Marker? _marker;

  @override
  void initState() {
    super.initState();
    // 若有傳入初始座標，直接使用；否則執行定位
    if (widget.initialPosition != null) {
      _setPosition(widget.initialPosition!);
    } else {
      _getCurrentLocation();
    }
  }

  /// 設定標記與相機初始位置
  void _setPosition(LatLng pos) {
    _currentPosition = pos;
    _marker = Marker(
      markerId: const MarkerId('selected-location'),
      position: pos,
      draggable: true,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      onDragEnd: (newPos) {
        setState(() {
          _currentPosition = newPos;
          _marker = _marker!.copyWith(positionParam: newPos);
        });
      },
    );
  }

  /// 取得目前 GPS 位置
  Future<void> _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      // 權限永遠拒絕，保留預設位置（無標記）
      return;
    }
    Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _setPosition(LatLng(pos.latitude, pos.longitude));
    });
  }

  /// 確認後回傳選擇座標
  void _onConfirm() {
    Navigator.pop(context, _currentPosition);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('選擇 GPS 位置', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue,
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _currentPosition,
          zoom: 16,
        ),
        onMapCreated: (controller) {
          _mapController = controller;
          // 啟動畫面時對準標記位置
          _mapController.animateCamera(
            CameraUpdate.newLatLng(_currentPosition),
          );
        },
        markers: _marker != null ? {_marker!} : {},
        onTap: (pos) {
          setState(() {
            _setPosition(pos);
          });
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onConfirm,
        child: const Icon(Icons.check),
        backgroundColor: Colors.blue,
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:http/http.dart' as http;
// import 'dart:typed_data';
//
// /// 自訂的 TileProvider 實作，用以取得台灣電子地圖圖磚，並加上 debug log
// class MyUrlTileProvider extends TileProvider {
//   final String urlTemplate;
//
//   MyUrlTileProvider({required this.urlTemplate});
//
//   @override
//   Future<Tile> getTile(int x, int y, int? zoom) async {
//     // 若 zoom 為 null 則指定預設縮放層級，例如 16
//     final int z = zoom ?? 16;
//     final String url = urlTemplate
//         .replaceAll('{z}', z.toString())
//         .replaceAll('{x}', x.toString())
//         .replaceAll('{y}', y.toString());
//
//     // 輸出 debug log：請求的圖磚 URL 以及 x, y, z 資訊
//     debugPrint("Fetching tile: x=$x, y=$y, z=$z");
//     debugPrint("URL: $url");
//
//     try {
//       final http.Response response = await http.get(Uri.parse(url));
//       debugPrint("HTTP Response: ${response.statusCode} for URL: $url");
//
//       if (response.statusCode == 200) {
//         debugPrint("Tile fetched successfully.");
//         return Tile(256, 256, response.bodyBytes);
//       } else {
//         debugPrint("Tile fetch error: HTTP ${response.statusCode} for URL: $url");
//       }
//     } catch (e) {
//       debugPrint("Exception while fetching tile from URL: $url");
//       debugPrint("Error: $e");
//     }
//     // 若發生錯誤則回傳空 tile
//     return Tile(256, 256, null);
//   }
// }
//
// class MapPickerPage extends StatefulWidget {
//   const MapPickerPage({Key? key}) : super(key: key);
//
//   @override
//   _MapPickerPageState createState() => _MapPickerPageState();
// }
//
// class _MapPickerPageState extends State<MapPickerPage> {
//   late GoogleMapController _mapController;
//   // 預設位置 (台北101附近)
//   LatLng _currentPosition = const LatLng(25.0330, 121.5654);
//   Marker? _marker;
//   Set<TileOverlay> _tileOverlays = {};
//
//   @override
//   void initState() {
//     super.initState();
//     _getCurrentLocation();
//     _initTileOverlay();
//   }
//
//   // 取得目前 GPS 位置
//   Future<void> _getCurrentLocation() async {
//     // 確認及請求定位權限
//     LocationPermission permission = await Geolocator.checkPermission();
//     if (permission == LocationPermission.denied) {
//       permission = await Geolocator.requestPermission();
//     }
//     if (permission == LocationPermission.deniedForever) {
//       // 無法取得權限，直接使用預設位置
//       return;
//     }
//     Position pos = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high);
//     setState(() {
//       _currentPosition = LatLng(pos.latitude, pos.longitude);
//       _marker = Marker(
//         markerId: const MarkerId('selected-location'),
//         position: _currentPosition,
//         draggable: true,
//         icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
//         onDragEnd: (newPosition) {
//           setState(() {
//             _currentPosition = newPosition;
//           });
//         },
//       );
//     });
//   }
//
//   // 建立台灣電子地圖的 TileOverlay
//   void _initTileOverlay() {
//     setState(() {
//       _tileOverlays.add(
//         TileOverlay(
//           tileOverlayId: const TileOverlayId('taiwanMap'),
//           tileProvider: MyUrlTileProvider(
//             urlTemplate:
//             'https://wmts.nlsc.gov.tw/wmts?REQUEST=GetTile&VERSION=1.0.0&LAYER=EMAP&STYLE=default&TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png',
//           ),
//         ),
//       );
//     });
//   }
//
//   // 確認選取後回傳選擇的座標
//   void _onConfirm() {
//     Navigator.pop(context, _currentPosition);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text(
//           '選擇 GPS 位置',
//           style: TextStyle(color: Colors.white),
//         ),
//         backgroundColor: Colors.blue,
//       ),
//       body: GoogleMap(
//         // 隱藏預設 Google 地圖圖磚
//         mapType: MapType.none,
//         initialCameraPosition: CameraPosition(
//           target: _currentPosition,
//           zoom: 16,
//         ),
//         onMapCreated: (controller) {
//           _mapController = controller;
//         },
//         markers: _marker != null ? {_marker!} : {},
//         tileOverlays: _tileOverlays,
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _onConfirm,
//         child: const Icon(Icons.check),
//         backgroundColor: Colors.blue,
//       ),
//     );
//   }
// }
