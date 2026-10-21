import 'dart:math';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The whole game is drawn in "design units": screen height is always 360.
const double kGround = 292; // y of the ground line
const double kRunnerX = 90; // runner's fixed x position
const double kGravity = 2500;

const String kGameName = 'SKY SPRINT'; // <- change the game name here
const int kStageLen = 600; // score needed to reach the next stage

/// Colors for one stage. Themes blend smoothly when the stage changes.
class StageTheme {
  const StageTheme({
    required this.name,
    required this.sky,
    required this.ridges,
    required this.grass,
    required this.dirt,
    required this.tuft,
    required this.sun,
    required this.cloud,
    required this.stars,
  });

  final String name;
  final List<Color> sky; // 5 colors, top to horizon
  final List<Color> ridges; // 3 mountain layers, far to near
  final List<Color> grass; // 2 colors
  final List<Color> dirt; // 2 colors
  final Color tuft, sun, cloud;
  final double stars; // 0 = no stars, 1 = full stars

  static List<Color> _l(List<Color> a, List<Color> b, double k) =>
      [for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], k)!];

  static StageTheme lerp(StageTheme a, StageTheme b, double k) => StageTheme(
        name: k < 0.5 ? a.name : b.name,
        sky: _l(a.sky, b.sky, k),
        ridges: _l(a.ridges, b.ridges, k),
        grass: _l(a.grass, b.grass, k),
        dirt: _l(a.dirt, b.dirt, k),
        tuft: Color.lerp(a.tuft, b.tuft, k)!,
        sun: Color.lerp(a.sun, b.sun, k)!,
        cloud: Color.lerp(a.cloud, b.cloud, k)!,
        stars: a.stars + (b.stars - a.stars) * k,
      );
}

const kThemes = <StageTheme>[
  StageTheme(
    name: 'SUNSET PEAKS',
    sky: [Color(0xFF10124A), Color(0xFF3D2C8D), Color(0xFFB5446E), Color(0xFFFF7E67), Color(0xFFFFC371)],
    ridges: [Color(0xFF8A4F9E), Color(0xFF5E3A85), Color(0xFF3B2A63)],
    grass: [Color(0xFF8EE08E), Color(0xFF3FA66B)],
    dirt: [Color(0xFF8B5A3C), Color(0xFF4A2E1E)],
    tuft: Color(0xFF6FD08C),
    sun: Color(0xFFFFF0C2),
    cloud: Color(0xFFFFE8E0),
    stars: 0.6,
  ),
  StageTheme(
    name: 'MIDNIGHT HILLS',
    sky: [Color(0xFF050818), Color(0xFF0B1240), Color(0xFF1B2A6B), Color(0xFF2E4A9A), Color(0xFF5C7FD1)],
    ridges: [Color(0xFF24306B), Color(0xFF182052), Color(0xFF0E1438)],
    grass: [Color(0xFF3E8E7E), Color(0xFF1F5E5A)],
    dirt: [Color(0xFF3A3150), Color(0xFF1C1830)],
    tuft: Color(0xFF58B3A0),
    sun: Color(0xFFE8EEFF),
    cloud: Color(0xFF9FB0E8),
    stars: 1.0,
  ),
  StageTheme(
    name: 'FROZEN SKY',
    sky: [Color(0xFF4F9AE0), Color(0xFF86C5F0), Color(0xFFB9E3F9), Color(0xFFD9F1FC), Color(0xFFF1FAFF)],
    ridges: [Color(0xFFA3C4E8), Color(0xFF7FA6D6), Color(0xFF5B82B8)],
    grass: [Color(0xFFF2FAFF), Color(0xFFBFDDF2)],
    dirt: [Color(0xFF8FA7C4), Color(0xFF5E7596)],
    tuft: Color(0xFFFFFFFF),
    sun: Color(0xFFFFFFFF),
    cloud: Color(0xFFFFFFFF),
    stars: 0.0,
  ),
  StageTheme(
    name: 'VOLCANO DUSK',
    sky: [Color(0xFF1A0B0B), Color(0xFF4A1410), Color(0xFF9C2F14), Color(0xFFE0571C), Color(0xFFFFA23A)],
    ridges: [Color(0xFF5A1D18), Color(0xFF3C1210), Color(0xFF220A0A)],
    grass: [Color(0xFF7A3B2A), Color(0xFF3D1C14)],
    dirt: [Color(0xFF3A1A12), Color(0xFF1A0A07)],
    tuft: Color(0xFFFF7B3A),
    sun: Color(0xFFFFD166),
    cloud: Color(0xFF7A3A2A),
    stars: 0.2,
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final prefs = await SharedPreferences.getInstance();
  final game = SkySprintGame(prefs);

  // Keyboard: Space / Up Arrow / W to jump, Enter to start or restart
  HardwareKeyboard.instance.addHandler((KeyEvent event) {
    if (event is KeyDownEvent) game.onKey(event.logicalKey);
    return false;
  });

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: GameWidget(game: game),
      ),
    ),
  );
}

enum GameState { menu, playing, dead }

class Obstacle {
  Obstacle(this.x, this.w, this.h, this.kind);
  double x;
  final double w, h;
  final int kind; // 0 = crystal spikes, 1 = tall gem, 2 = crate
}

class Coin {
  Coin(this.x, this.h);
  double x;
  final double h; // height above ground
  bool taken = false;
}

class Cloud {
  Cloud(this.x, this.y, this.s, this.v);
  double x, y;
  final double s, v;
}

class Spark {
  Spark(this.x, this.y, this.vx, this.vy, this.life, this.size, this.color)
      : maxLife = life;
  double x, y, vx, vy, life;
  final double size, maxLife;
  final Color color;
}

class SkySprintGame extends FlameGame with TapCallbacks {
  SkySprintGame(this.prefs) {
    best = prefs.getInt('best') ?? 0;
    coins = prefs.getInt('coins') ?? 0;
  }

  final SharedPreferences prefs;
  final Random rnd = Random();

  GameState state = GameState.menu;
  int best = 0, coins = 0, runCoins = 0, bonus = 0, jumps = 0;
  bool newBest = false, grounded = true;
  double t = 0, scroll = 0, distance = 0, speed = 330;
  double ry = 0, vy = 0, squash = 0, shake = 0;
  double deadT = 0, dustT = 0, nextSpawnDist = 400;

  final obstacles = <Obstacle>[];
  final coinList = <Coin>[];
  final sparks = <Spark>[];
  final clouds = <Cloud>[];

  int stage = 0;
  double blend = 1, bannerT = 0;
  StageTheme from = kThemes[0], to = kThemes[0];

  StageTheme _theme() => StageTheme.lerp(
      from, to, Curves.easeInOut.transform(blend.clamp(0.0, 1.0).toDouble()));

  double get w => size.x / (size.y / 360);
  int get score => (distance / 12).floor() + bonus;

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < 7; i++) {
      clouds.add(Cloud(
        rnd.nextDouble() * 900,
        20 + rnd.nextDouble() * 130,
        0.7 + rnd.nextDouble() * 0.9,
        6 + rnd.nextDouble() * 10,
      ));
    }
  }

  // ---------------------------------------------------------------- input

  @override
  void onTapDown(TapDownEvent event) => _action();

  void onKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _action();
    }
  }

  void _action() {
    if (state == GameState.menu) {
      _start();
    } else if (state == GameState.playing) {
      _jump();
    } else if (deadT > 0.6) {
      _start();
    }
  }

  void _start() {
    state = GameState.playing;
    obstacles.clear();
    coinList.clear();
    sparks.clear();
    distance = 0;
    bonus = 0;
    runCoins = 0;
    speed = 330;
    ry = 0;
    vy = 0;
    jumps = 0;
    grounded = true;
    newBest = false;
    deadT = 0;
    nextSpawnDist = 400;
    shake = 0;
    squash = 0;
    stage = 0;
    from = kThemes[0];
    to = kThemes[0];
    blend = 0;
    bannerT = 0;
  }

  void _jump() {
    if (jumps >= 2) return;
    vy = jumps == 0 ? 800.0 : 700.0;
    jumps++;
    grounded = false;
    squash = -1;
    _dust(kRunnerX + 12, kGround - ry, jumps == 1 ? 5 : 3);
  }

  void _die() {
    state = GameState.dead;
    deadT = 0;
    shake = 14;
    final cx = kRunnerX + 17;
    final cy = kGround - ry - 28;
    _burst(cx, cy, 26, const Color(0xFF4CC9F0), 220, 4);
    _burst(cx, cy, 14, const Color(0xFFFF4D6D), 180, 3);
    _burst(cx, cy, 10, const Color(0xFFFFD6A5), 150, 3);
    if (score > best) {
      best = score;
      newBest = true;
      prefs.setInt('best', best);
    }
    prefs.setInt('coins', coins);
  }

  // --------------------------------------------------------------- update

  @override
  void update(double dt) {
    super.update(dt);
    dt = min(dt, 0.033);
    t += dt;
    final running = state == GameState.playing;

    for (final c in clouds) {
      c.x -= (c.v + (running ? speed * 0.04 * c.s : 0.0)) * dt;
      if (c.x < -120) {
        c.x = w + 40 + rnd.nextDouble() * 120;
        c.y = 20 + rnd.nextDouble() * 130;
      }
    }

    squash += (0 - squash) * min(1.0, dt * 12);
    blend = min(1.0, blend + dt / 2);
    if (bannerT > 0) bannerT = max(0.0, bannerT - dt);
    shake = shake < 0.2 ? 0.0 : shake * exp(-9 * dt);

    if (state == GameState.menu) {
      scroll += 90 * dt;
      _runDust(dt);
    } else if (state == GameState.playing) {
      _updatePlaying(dt);
    } else {
      deadT += dt;
    }

    for (final s in sparks) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vy += 500 * dt;
      s.life -= dt;
    }
    sparks.removeWhere((s) => s.life <= 0);
  }

  void _runDust(double dt) {
    dustT -= dt;
    if (grounded && dustT <= 0) {
      _dust(kRunnerX + 6, kGround, 1);
      dustT = 0.06;
    }
  }

  void _updatePlaying(double dt) {
    speed = min(330 + distance * 0.012, 640.0);
    distance += speed * dt;
    scroll += speed * dt;

    // stage progression
    final st = score ~/ kStageLen;
    if (st != stage) {
      from = _theme();
      stage = st;
      to = kThemes[stage % kThemes.length];
      blend = 0;
      bannerT = 3;
      bonus += 25;
      _burst(w * 0.5, 120, 30, const Color(0xFFFFD166), 260, 3);
    }

    // physics
    vy -= kGravity * dt;
    ry += vy * dt;
    if (ry <= 0) {
      if (!grounded) {
        squash = 1;
        _dust(kRunnerX + 12, kGround, 6);
      }
      ry = 0;
      vy = 0;
      grounded = true;
      jumps = 0;
    }
    _runDust(dt);

    // spawning
    nextSpawnDist -= speed * dt;
    if (nextSpawnDist <= 0) {
      _spawnObstacle();
    }

    for (final o in obstacles) {
      o.x -= speed * dt;
    }
    for (final k in coinList) {
      k.x -= speed * dt;
    }
    obstacles.removeWhere((o) => o.x + o.w < -20);
    coinList.removeWhere((k) => k.taken || k.x < -20);

    // coins
    final rc = Offset(kRunnerX + 17, kGround - ry - 28);
    for (final k in coinList) {
      if (k.taken) continue;
      final p = Offset(k.x, kGround - k.h);
      if ((p - rc).distance < 26) {
        k.taken = true;
        coins++;
        runCoins++;
        bonus += 5;
        _burst(p.dx, p.dy, 8, const Color(0xFFFFD166), 120, 2.5);
      }
    }

    // collisions
    final hit = Rect.fromLTWH(kRunnerX + 7, kGround - ry - 54, 20, 50);
    for (final o in obstacles) {
      final r = Rect.fromLTWH(o.x + 6, kGround - o.h + 8, o.w - 12, o.h - 8);
      if (hit.overlaps(r)) {
        _die();
        return;
      }
    }
  }

  void _spawnObstacle() {
    // stage 1 uses spikes and crates only; later stages add tall gems
    final kind = stage == 0 ? (rnd.nextBool() ? 0 : 2) : rnd.nextInt(3);
    double ow;
    double oh;
    if (kind == 0) {
      ow = 26.0 * (1 + rnd.nextInt(3));
      oh = 32;
    } else if (kind == 1) {
      ow = 34;
      oh = 52 + rnd.nextInt(14).toDouble();
    } else {
      ow = 44;
      oh = 44;
    }
    final x = w + 40;
    obstacles.add(Obstacle(x, ow, oh, kind));

    if (rnd.nextDouble() < 0.75) {
      const n = 5;
      for (var i = 0; i < n; i++) {
        final f = i / (n - 1);
        coinList.add(Coin(x + ow / 2 + (f - 0.5) * 130, oh + 28 + sin(f * pi) * 55));
      }
    }
    nextSpawnDist = speed * 0.72 + 160 + rnd.nextDouble() * 240;
  }

  void _burst(double x, double y, int n, Color color, double spd, double size) {
    for (var i = 0; i < n; i++) {
      final a = rnd.nextDouble() * 2 * pi;
      final s = rnd.nextDouble() * spd;
      sparks.add(Spark(x, y, cos(a) * s, sin(a) * s - 40,
          0.4 + rnd.nextDouble() * 0.5, size * (0.5 + rnd.nextDouble()), color));
    }
  }

  void _dust(double x, double y, int n) {
    for (var i = 0; i < n; i++) {
      sparks.add(Spark(
        x + rnd.nextDouble() * 8,
        y - 2,
        -30 - rnd.nextDouble() * 70,
        -rnd.nextDouble() * 45,
        0.3 + rnd.nextDouble() * 0.25,
        2 + rnd.nextDouble() * 2,
        const Color(0xFFFFE8D6),
      ));
    }
  }

  // --------------------------------------------------------------- render

  Paint _p(Color c) => Paint()..color = c;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final u = size.y / 360;
    final w = size.x / u;
    canvas.save();
    canvas.scale(u);
    if (shake > 0) {
      canvas.translate((rnd.nextDouble() - 0.5) * shake, (rnd.nextDouble() - 0.5) * shake);
    }

    final th = _theme();
    _drawSky(canvas, w, th);
    for (final c in clouds) {
      _drawCloud(canvas, c, th);
    }
    _ridge(canvas, w, 235, 55, 0.007, 0.05, th.ridges[0]);
    _ridge(canvas, w, 262, 38, 0.012, 0.12, th.ridges[1]);
    _ridge(canvas, w, 280, 22, 0.02, 0.25, th.ridges[2]);
    _drawGround(canvas, w, th);

    for (final k in coinList) {
      _drawCoin(canvas, k);
    }
    for (final o in obstacles) {
      _drawObstacle(canvas, o);
    }
    if (state != GameState.dead) {
      _drawRunner(canvas);
    }
    for (final s in sparks) {
      final a = (s.life / s.maxLife).clamp(0.0, 1.0).toDouble();
      canvas.drawCircle(Offset(s.x, s.y), s.size * (0.4 + 0.6 * a),
          _p(s.color.withValues(alpha: a)));
    }

    // soft vignette
    final vr = Rect.fromLTWH(0, 0, w, 360);
    canvas.drawRect(
      vr,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.95,
          colors: [Color(0x00000000), Color(0x59000000)],
          stops: [0.65, 1.0],
        ).createShader(vr),
    );

    if (state == GameState.playing) _drawHud(canvas, w);
    if (state == GameState.menu) _drawMenu(canvas, w);
    if (state == GameState.dead) _drawGameOver(canvas, w);
    canvas.restore();
  }

  void _drawSky(Canvas c, double w, StageTheme th) {
    final r = Rect.fromLTWH(0, 0, w, 360);
    c.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: th.sky,
          stops: const [0.0, 0.35, 0.62, 0.82, 1.0],
        ).createShader(r),
    );
    // twinkling stars
    for (var i = 0; i < 45; i++) {
      final sx = ((i * 97) % 101) / 101 * w;
      final sy = ((i * 53) % 61) / 61 * 170;
      final a = (0.35 + 0.35 * sin(t * 2 + i)) * th.stars;
      c.drawCircle(Offset(sx, sy), 0.7 + (i % 3) * 0.4,
          _p(Colors.white.withValues(alpha: a)));
    }
    // sun with glow
    final sun = Offset(w * 0.7, 230);
    c.drawCircle(
      sun,
      130,
      Paint()
        ..shader = RadialGradient(
          colors: [th.sun.withValues(alpha: 0.8), th.sun.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: sun, radius: 130)),
    );
    c.drawCircle(sun, 40, _p(th.sun));
  }

  void _drawCloud(Canvas c, Cloud cl, StageTheme th) {
    final p = _p(th.cloud.withValues(alpha: 0.5 + cl.s * 0.2));
    final s = cl.s;
    c.drawCircle(Offset(cl.x, cl.y), 18 * s, p);
    c.drawCircle(Offset(cl.x + 20 * s, cl.y - 8 * s), 24 * s, p);
    c.drawCircle(Offset(cl.x + 44 * s, cl.y), 18 * s, p);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cl.x - 8 * s, cl.y, 70 * s, 18 * s),
        Radius.circular(9 * s),
      ),
      p,
    );
  }

  void _ridge(Canvas c, double w, double base, double amp, double freq,
      double parallax, Color color) {
    final path = Path()..moveTo(0, 360);
    for (double x = 0; x <= w + 8; x += 8) {
      final xx = x + scroll * parallax;
      final y = base -
          amp *
              (0.55 * sin(xx * freq) +
                  0.30 * sin(xx * freq * 2.3 + 1.7) +
                  0.15 * sin(xx * freq * 4.1 + 0.6));
      path.lineTo(x, y);
    }
    path.lineTo(w, 360);
    path.close();
    c.drawPath(path, _p(color));
  }

  void _drawGround(Canvas c, double w, StageTheme th) {
    final grass = Rect.fromLTWH(0, kGround, w, 16);
    c.drawRect(
      grass,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: th.grass,
        ).createShader(grass),
    );
    final dirt = Rect.fromLTWH(0, kGround + 16, w, 360 - kGround - 16);
    c.drawRect(
      dirt,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: th.dirt,
        ).createShader(dirt),
    );
    final tuft = _p(th.tuft);
    final off = scroll % 38;
    for (double x = -off; x < w + 38; x += 38) {
      final p = Path()
        ..moveTo(x, kGround)
        ..lineTo(x + 4, kGround - 9)
        ..lineTo(x + 8, kGround)
        ..lineTo(x + 12, kGround - 6)
        ..lineTo(x + 15, kGround)
        ..close();
      c.drawPath(p, tuft);
    }
    final off2 = scroll % 72;
    for (double x = -off2; x < w + 72; x += 72) {
      final idx = ((x + scroll) / 72).round();
      final yy = kGround + 34 + (idx % 3) * 16.0;
      c.drawOval(
        Rect.fromCenter(
            center: Offset(x + 20, yy), width: 16 + (idx % 2) * 8.0, height: 8),
        _p(const Color(0x33000000)),
      );
    }
    c.drawRect(Rect.fromLTWH(0, kGround, w, 2), _p(const Color(0x66FFFFFF)));
  }

  void _coinFace(Canvas c, double r) {
    c.drawCircle(Offset.zero, r, _p(const Color(0xFFE09F3E)));
    c.drawCircle(Offset.zero, r - 2.5, _p(const Color(0xFFFFD166)));
    c.drawCircle(Offset(-r * 0.25, -r * 0.25), r * 0.28, _p(const Color(0xFFFFF3B0)));
  }

  void _drawCoin(Canvas c, Coin k) {
    final p = Offset(k.x, kGround - k.h);
    final sx = max(0.25, cos(t * 5 + k.x * 0.04).abs());
    c.drawCircle(p, 15, _p(const Color(0x33FFD166)));
    c.save();
    c.translate(p.dx, p.dy);
    c.scale(sx, 1.0);
    _coinFace(c, 9);
    c.restore();
  }

  void _drawObstacle(Canvas c, Obstacle o) {
    final x = o.x;
    final w = o.w;
    final h = o.h;
    c.drawOval(Rect.fromLTWH(x - 4, kGround - 4, w + 8, 10),
        _p(const Color(0x33000000)));

    if (o.kind == 0) {
      final n = (w / 26).round();
      for (var i = 0; i < n; i++) {
        final x0 = x + i * 26;
        final dark = Path()
          ..moveTo(x0, kGround)
          ..lineTo(x0 + 13, kGround - h)
          ..lineTo(x0 + 13, kGround)
          ..close();
        final light = Path()
          ..moveTo(x0 + 13, kGround - h)
          ..lineTo(x0 + 26, kGround)
          ..lineTo(x0 + 13, kGround)
          ..close();
        c.drawPath(dark, _p(const Color(0xFF7B2CBF)));
        c.drawPath(light, _p(const Color(0xFFC77DFF)));
      }
    } else if (o.kind == 1) {
      final top = Offset(x + w / 2, kGround - h);
      final l = Offset(x, kGround - h * 0.6);
      final r = Offset(x + w, kGround - h * 0.6);
      final bl = Offset(x + w * 0.15, kGround);
      final br = Offset(x + w * 0.85, kGround);
      final bc = Offset(x + w / 2, kGround);
      final left = Path()
        ..moveTo(top.dx, top.dy)
        ..lineTo(l.dx, l.dy)
        ..lineTo(bl.dx, bl.dy)
        ..lineTo(bc.dx, bc.dy)
        ..close();
      final right = Path()
        ..moveTo(top.dx, top.dy)
        ..lineTo(r.dx, r.dy)
        ..lineTo(br.dx, br.dy)
        ..lineTo(bc.dx, bc.dy)
        ..close();
      c.drawPath(left, _p(const Color(0xFF0096C7)));
      c.drawPath(right, _p(const Color(0xFF48CAE4)));
      c.drawCircle(Offset(x + w * 0.36, kGround - h * 0.7), 2.2,
          _p(Colors.white.withValues(alpha: 0.8)));
    } else {
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, kGround - h, w, h), const Radius.circular(5));
      c.drawRRect(rr, _p(const Color(0xFFC9884B)));
      final line = Paint()
        ..color = const Color(0xFF7A4B24)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      c.drawLine(Offset(x + 6, kGround - h + 6), Offset(x + w - 6, kGround - 6), line);
      c.drawLine(Offset(x + w - 6, kGround - h + 6), Offset(x + 6, kGround - 6), line);
      c.drawRRect(
        rr,
        Paint()
          ..color = const Color(0xFF7A4B24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  void _drawRunner(Canvas c) {
    final cx = kRunnerX + 17;
    final fy = kGround - ry;

    // ground shadow
    final sh = (1 - min(ry, 160.0) / 220) * 30;
    c.drawOval(
      Rect.fromCenter(center: Offset(cx, kGround + 4), width: sh, height: sh * 0.28),
      _p(const Color(0x40000000)),
    );

    c.save();
    c.translate(cx, fy);
    c.scale(1 + 0.22 * squash, 1 - 0.22 * squash);

    final air = !grounded;
    final phase = t * 20;

    // scarf (behind the body)
    final scarf = Paint()
      ..color = const Color(0xFFFF4D6D)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final sp = Path()..moveTo(-6, -34);
    final amp = air ? 4.0 : 2.5;
    for (var i = 1; i <= 5; i++) {
      final lift = air ? (vy > 0 ? i * 1.5 : -i * 1.5) : 0.0;
      sp.lineTo(-6 - i * 7.0, -34 + sin(t * 16 - i * 0.9) * amp * i * 0.6 + lift);
    }
    c.drawPath(sp, scarf);

    // legs
    final legPaint = Paint()
      ..color = const Color(0xFF2B2D42)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final shoe = _p(const Color(0xFFEF476F));
    for (var i = 0; i < 2; i++) {
      final ph = phase + i * pi;
      final fx = air ? (i == 0 ? 8.0 : -6.0) : sin(ph) * 11;
      final fyy = air ? (i == 0 ? -10.0 : -14.0) : -3 - max(0.0, cos(ph)) * 7;
      c.drawLine(const Offset(0, -14), Offset(fx, fyy), legPaint);
      c.drawCircle(Offset(fx + 2, fyy), 4.5, shoe);
    }

    // body
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(-12, -37, 12, -12), const Radius.circular(10)),
      _p(const Color(0xFF4CC9F0)),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(-5, -32, 9, -17), const Radius.circular(7)),
      _p(const Color(0xFF9BE7FA)),
    );

    // arm
    final armSwing = air ? 0.8 : sin(phase + pi);
    final armEndY = air ? -30.0 : -22.0;
    c.drawLine(
      const Offset(2, -30),
      Offset(2 + armSwing * 9, armEndY),
      Paint()
        ..color = const Color(0xFFFFD6A5)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    // head
    const hc = Offset(1, -46);
    c.drawCircle(hc, 13, _p(const Color(0xFFFFD6A5)));
    c.drawArc(Rect.fromCircle(center: hc, radius: 13), pi, pi, true,
        _p(const Color(0xFF3D2C8D)));
    c.drawLine(
      const Offset(-12, -45),
      const Offset(14, -45),
      Paint()
        ..color = const Color(0xFFFF9F1C)
        ..strokeWidth = 4,
    );
    c.drawCircle(const Offset(7, -45), 6, _p(Colors.white));
    c.drawCircle(const Offset(8.5, -45), 2.5, _p(const Color(0xFF2B2D42)));

    c.restore();
  }

  // ------------------------------------------------------------------ UI

  void _text(
    Canvas c,
    String s,
    Offset pos, {
    double size = 20,
    Color color = Colors.white,
    double spacing = 0,
    Alignment align = Alignment.center,
    bool shadow = true,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: spacing,
          shadows: shadow
              ? const [
                  Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 2))
                ]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      c,
      Offset(pos.dx - tp.width * (align.x + 1) / 2,
          pos.dy - tp.height * (align.y + 1) / 2),
    );
  }

  void _button(Canvas c, Offset center, String label, double bw, double bh,
      double fs) {
    c.save();
    c.translate(center.dx, center.dy);
    final k = 1 + 0.04 * sin(t * 5);
    c.scale(k, k);
    final r = Radius.circular(bh / 2);
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(0, 4), width: bw, height: bh), r),
      _p(const Color(0xFFC76F00)),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: bw, height: bh), r),
      _p(const Color(0xFFFFB703)),
    );
    _text(c, label, Offset.zero,
        size: fs, color: const Color(0xFF3A0CA3), spacing: 2, shadow: false);
    c.restore();
  }

  void _drawHud(Canvas c, double w) {
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(14, 12, 96, 32), const Radius.circular(16)),
      _p(const Color(0x59000000)),
    );
    c.save();
    c.translate(32, 28);
    _coinFace(c, 10);
    c.restore();
    _text(c, '$coins', const Offset(48, 28),
        size: 18, align: Alignment.centerLeft);
    _text(c, '$score', Offset(w / 2, 34), size: 38);
    _text(c, 'BEST $best', Offset(w - 16, 28),
        size: 14,
        color: const Color(0xFFFFE8D6),
        align: Alignment.centerRight);
    _text(c, 'STAGE ${stage + 1}  -  ${_theme().name}', Offset(w / 2, 66),
        size: 13, color: const Color(0xFFFFE8D6), spacing: 2);
    if (bannerT > 0) {
      final a = min(1.0, min(bannerT * 2, (3 - bannerT) * 4)).clamp(0.0, 1.0).toDouble();
      _text(c, 'STAGE ${stage + 1}', Offset(w / 2, 150),
          size: 52, color: Colors.white.withValues(alpha: a), spacing: 6);
      _text(c, to.name, Offset(w / 2, 192),
          size: 20, color: const Color(0xFFFFD166).withValues(alpha: a), spacing: 5);
    }
  }

  void _drawMenu(Canvas c, double w) {
    final ty = 96 + sin(t * 2) * 4;
    final ts = min(64.0, (w * 0.9) / (kGameName.length * 0.7));
    _text(c, kGameName, Offset(w / 2, ty + 5),
        size: ts, color: const Color(0xFF3A0CA3), spacing: 4, shadow: false);
    _text(c, kGameName, Offset(w / 2, ty),
        size: ts, color: const Color(0xFFFFF1D0), spacing: 4, shadow: false);
    _text(c, 'ENDLESS RUNNER', Offset(w / 2, ty + 48),
        size: 15, color: const Color(0xFFFFD6A5), spacing: 7);
    _button(c, Offset(w / 2, 232), 'TAP TO START', 230, 48, 22);
    if (best > 0) {
      _text(c, 'BEST  $best', Offset(w / 2, 276),
          size: 16, color: const Color(0xFFFFF1D0));
    }
  }

  void _drawGameOver(Canvas c, double w) {
    c.drawRect(Rect.fromLTWH(0, 0, w, 360), _p(const Color(0x73000000)));
    final k = Curves.easeOutBack.transform(min(1.0, deadT * 4));
    c.save();
    c.translate(w / 2, 195);
    c.scale(k, k);
    final panel = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 300, height: 230),
      const Radius.circular(22),
    );
    c.drawRRect(panel.shift(const Offset(0, 6)), _p(const Color(0x66000000)));
    c.drawRRect(panel, _p(const Color(0xF22B1B5C)));
    c.drawRRect(
      panel,
      Paint()
        ..color = const Color(0xFFFFB703)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    _text(c, 'GAME OVER', const Offset(0, -84),
        size: 32, color: const Color(0xFFFF4D6D), spacing: 2);
    _text(c, 'SCORE', const Offset(0, -52),
        size: 13, color: const Color(0xFFB8A9E8), spacing: 3);
    _text(c, '$score', const Offset(0, -20), size: 46);
    if (newBest) {
      _text(c, 'NEW BEST!', const Offset(0, 22),
          size: 18 + sin(t * 8) * 1.5, color: const Color(0xFF80ED99));
    } else {
      _text(c, 'BEST  $best', const Offset(0, 22),
          size: 18, color: const Color(0xFFFFD166));
    }
    _text(c, 'STAGE ${stage + 1}    COINS  +$runCoins', const Offset(0, 48),
        size: 16, color: const Color(0xFFFFD166));
    if (deadT > 0.6) {
      _button(c, const Offset(0, 86), 'TAP TO PLAY AGAIN', 240, 40, 17);
    }
    c.restore();
  }
}