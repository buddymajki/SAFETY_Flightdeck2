import 'dart:io';

void main() {
  final startLat = 47.167756660953295;
  final startLng = 8.118202815919576;
  final endLat = 47.37114429751757;
  final endLng = 7.991635020439488;
  final altitude = 1000; // 2000m to trigger airspace violations
  final startTime = DateTime.utc(2026, 1, 21, 11, 0, 0);
  final steps = 3600; // 60 perc, 3601 pont (0..3600)

  final buffer = StringBuffer();
  buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">');
  buffer.writeln('<Document>');
  buffer.writeln('  <name>CTR Violation Test Flight (Full)</name>');
  buffer.writeln('  <Placemark>');
  buffer.writeln('    <name>Test Flight Path</name>');
  buffer.writeln('    <gx:Track>');
  buffer.writeln('      <altitudeMode>absolute</altitudeMode>');

  for (int i = 0; i <= steps; i++) {
    final frac = i / steps;
    final lat = startLat + (endLat - startLat) * frac;
    final lng = startLng + (endLng - startLng) * frac;
    final t = startTime.add(Duration(seconds: i));
    buffer.writeln('      <when>${t.toIso8601String().replaceFirst('.000Z', 'Z')}</when>');
    buffer.writeln('      <gx:coord>${lng.toStringAsFixed(12)} ${lat.toStringAsFixed(12)} $altitude</gx:coord>');
  }

  buffer.writeln('    </gx:Track>');
  buffer.writeln('  </Placemark>');
  buffer.writeln('</Document>');
  buffer.writeln('</kml>');

  File('test_flight_ctr_full.kml').writeAsStringSync(buffer.toString());
}