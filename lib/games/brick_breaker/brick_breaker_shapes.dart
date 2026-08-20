import 'dart:math' as math;
import 'dart:ui';

enum BrickShape { round, triTL, triTR, triBL, triBR }

class BrickShapeUtil {
  static BrickShape pick(math.Random rng) {
    if (rng.nextDouble() > 0.5) {
      final i = rng.nextInt(4);
      return [BrickShape.triTL, BrickShape.triTR, BrickShape.triBL, BrickShape.triBR][i];
    }
    return BrickShape.round;
  }

  static List<Offset> triangleVerts(BrickShape shape, double hw, double hh) {
    switch (shape) {
      case BrickShape.triTL:
        return [Offset(-hw, -hh), Offset(hw, -hh), Offset(-hw, hh)];
      case BrickShape.triTR:
        return [Offset(-hw, -hh), Offset(hw, -hh), Offset(hw, hh)];
      case BrickShape.triBL:
        return [Offset(-hw, -hh), Offset(-hw, hh), Offset(hw, hh)];
      case BrickShape.triBR:
        return [Offset(hw, -hh), Offset(hw, hh), Offset(-hw, hh)];
      case BrickShape.round:
        return const [];
    }
  }

  static Path brickPath(BrickShape shape, double hw, double hh) {
    final path = Path();
    final cr = math.min(hw, hh) * 0.24;
    if (shape == BrickShape.round) {
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: hw * 2, height: hh * 2),
          Radius.circular(math.min(hw, hh) * 0.38),
        ),
      );
      return path;
    }
    final tri = triangleVerts(shape, hw, hh);
    final ax = tri[0].dx;
    final ay = tri[0].dy;
    final bx = tri[1].dx;
    final by = tri[1].dy;
    final cx = tri[2].dx;
    final cy = tri[2].dy;
    final abx = bx - ax;
    final aby = by - ay;
    final acx = cx - ax;
    final acy = cy - ay;
    final lab = math.max(math.hypot(abx, aby), 1e-8);
    final lac = math.max(math.hypot(acx, acy), 1e-8);
    final uabx = abx / lab;
    final uaby = aby / lab;
    final uacx = acx / lac;
    final uacy = acy / lac;
    path.moveTo(ax + uabx * cr, ay + uaby * cr);
    path.lineTo(bx, by);
    path.lineTo(cx, cy);
    path.lineTo(ax + uacx * cr, ay + uacy * cr);
    path.quadraticBezierTo(ax, ay, ax + uabx * cr, ay + uaby * cr);
    path.close();
    return path;
  }

  static bool _pointInConvex(double px, double py, List<Offset> verts) {
    var sign = 0;
    for (var i = 0; i < verts.length; i++) {
      final x1 = verts[i].dx;
      final y1 = verts[i].dy;
      final x2 = verts[(i + 1) % verts.length].dx;
      final y2 = verts[(i + 1) % verts.length].dy;
      final cross = (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1);
      if (cross.abs() < 1e-8) continue;
      if (sign == 0) {
        sign = cross.sign.toInt();
      } else if (cross.sign.toInt() != sign) {
        return false;
      }
    }
    return true;
  }

  static ({double lnx, double lny, double depth})? _localHitRoundRect(
    double lx,
    double ly,
    double br,
    double hw,
    double hh,
  ) {
    final clx = lx.clamp(-hw, hw);
    final cly = ly.clamp(-hh, hh);
    var nx = lx - clx;
    var ny = ly - cly;
    final lenSq = nx * nx + ny * ny;
    if (lenSq >= br * br) return null;

    if (lenSq < 1e-8) {
      final penL = lx + hw;
      final penR = hw - lx;
      final penT = ly + hh;
      final penB = hh - ly;
      var min = penL;
      var lnx = -1.0;
      var lny = 0.0;
      if (penR < min) {
        min = penR;
        lnx = 1;
        lny = 0;
      }
      if (penT < min) {
        min = penT;
        lnx = 0;
        lny = -1;
      }
      if (penB < min) {
        min = penB;
        lnx = 0;
        lny = 1;
      }
      return (lnx: lnx, lny: lny, depth: min);
    }
    final len = math.sqrt(lenSq);
    return (lnx: nx / len, lny: ny / len, depth: br - len);
  }

  static ({double lnx, double lny, double depth})? _localHitTriangle(
    double lx,
    double ly,
    double br,
    List<Offset> verts,
  ) {
    var bestDistSq = double.infinity;
    var bestPx = lx;
    var bestPy = ly;
    for (var i = 0; i < verts.length; i++) {
      final x1 = verts[i].dx;
      final y1 = verts[i].dy;
      final x2 = verts[(i + 1) % verts.length].dx;
      final y2 = verts[(i + 1) % verts.length].dy;
      final dx = x2 - x1;
      final dy = y2 - y1;
      final t = ((lx - x1) * dx + (ly - y1) * dy) / (dx * dx + dy * dy + 1e-8);
      final tc = t.clamp(0.0, 1.0);
      final px = x1 + dx * tc;
      final py = y1 + dy * tc;
      final ddx = lx - px;
      final ddy = ly - py;
      final dsq = ddx * ddx + ddy * ddy;
      if (dsq < bestDistSq) {
        bestDistSq = dsq;
        bestPx = px;
        bestPy = py;
      }
    }
    final inside = _pointInConvex(lx, ly, verts);
    if (!inside && bestDistSq >= br * br) return null;

    var nx = lx - bestPx;
    var ny = ly - bestPy;
    if (inside && nx * nx + ny * ny < 1e-8) {
      var minPen = double.infinity;
      var lnx = 1.0;
      var lny = 0.0;
      final cx = verts.map((v) => v.dx).reduce((a, b) => a + b) / verts.length;
      final cy = verts.map((v) => v.dy).reduce((a, b) => a + b) / verts.length;
      for (var i = 0; i < verts.length; i++) {
        final x1 = verts[i].dx;
        final y1 = verts[i].dy;
        final x2 = verts[(i + 1) % verts.length].dx;
        final y2 = verts[(i + 1) % verts.length].dy;
        var enx = y2 - y1;
        var eny = -(x2 - x1);
        final el = math.max(math.hypot(enx, eny), 1e-8);
        enx /= el;
        eny /= el;
        final mx = (x1 + x2) / 2;
        final my = (y1 + y2) / 2;
        if (enx * (cx - mx) + eny * (cy - my) < 0) {
          enx = -enx;
          eny = -eny;
        }
        final pen = (lx - x1) * enx + (ly - y1) * eny;
        if (pen < minPen) {
          minPen = pen;
          lnx = enx;
          lny = eny;
        }
      }
      return (lnx: lnx, lny: lny, depth: -minPen);
    }
    final len = math.max(math.hypot(nx, ny), 1e-8);
    return (lnx: nx / len, lny: ny / len, depth: br - len);
  }

  static ({double nx, double ny, double depth})? ballHit({
    required double bx,
    required double by,
    required double br,
    required double cx,
    required double cy,
    required double hw,
    required double hh,
    required double angle,
    required BrickShape shape,
  }) {
    final cos = math.cos(-angle);
    final sin = math.sin(-angle);
    final dx = bx - cx;
    final dy = by - cy;
    final lx = dx * cos - dy * sin;
    final ly = dx * sin + dy * cos;

    final ({double lnx, double lny, double depth})? hit;
    if (shape == BrickShape.round) {
      hit = _localHitRoundRect(lx, ly, br, hw, hh);
    } else {
      hit = _localHitTriangle(lx, ly, br, triangleVerts(shape, hw, hh));
    }
    if (hit == null) return null;

    final cosW = math.cos(angle);
    final sinW = math.sin(angle);
    return (
      nx: hit.lnx * cosW - hit.lny * sinW,
      ny: hit.lnx * sinW + hit.lny * cosW,
      depth: hit.depth,
    );
  }
}
