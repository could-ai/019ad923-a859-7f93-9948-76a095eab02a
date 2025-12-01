import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const BrickBreakerApp());
}

class BrickBreakerApp extends StatelessWidget {
  const BrickBreakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brick Out Ultra Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  
  // Game State
  int score = 0;
  int highScore = 0;
  int level = 1;
  int lives = 3;
  bool isPlaying = false;
  bool isGameOver = false;
  bool isPaused = false;

  // Physics Entities
  late Paddle paddle;
  List<Ball> balls = [];
  List<Brick> bricks = [];
  List<PowerUp> powerUps = [];
  List<Particle> particles = [];

  // Screen Size
  Size screenSize = Size.zero;

  // Settings
  double difficultyMultiplier = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(_update);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _initGame(Size size) {
    screenSize = size;
    paddle = Paddle(
      x: size.width / 2 - 50,
      y: size.height - 80,
      width: 100,
      height: 20,
      color: Colors.cyanAccent,
    );
    
    _resetBall();
    _buildLevel(level);
    
    score = 0;
    lives = 3;
    level = 1;
    isGameOver = false;
    isPlaying = false;
  }

  void _resetBall() {
    balls.clear();
    balls.add(Ball(
      x: paddle.x + paddle.width / 2,
      y: paddle.y - 20,
      dx: 0,
      dy: 0, // Stationary until launch
      speed: 6.0 * difficultyMultiplier,
      color: Colors.white,
      isStuckToPaddle: true,
    ));
  }

  void _launchBall() {
    if (balls.isNotEmpty && balls.first.isStuckToPaddle) {
      balls.first.isStuckToPaddle = false;
      balls.first.dx = (math.Random().nextBool() ? 1 : -1) * 4.0;
      balls.first.dy = -balls.first.speed;
      isPlaying = true;
      _controller.forward();
    }
  }

  void _buildLevel(int lvl) {
    bricks.clear();
    powerUps.clear();
    particles.clear();
    
    int rows = 5 + (lvl % 5);
    int cols = 6 + (lvl % 3);
    double padding = 10;
    double brickWidth = (screenSize.width - (padding * (cols + 1))) / cols;
    double brickHeight = 25;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        // Skip some bricks for patterns
        if (math.Random().nextDouble() > 0.9) continue;

        BrickType type = BrickType.normal;
        int health = 1;
        Color color = Colors.primaries[(r + c) % Colors.primaries.length];

        // Advanced Brick Types
        double rand = math.Random().nextDouble();
        if (rand > 0.95) {
          type = BrickType.explosive;
          color = Colors.redAccent;
        } else if (rand > 0.9) {
          type = BrickType.hard;
          health = 3;
          color = Colors.grey;
        } else if (rand > 0.85) {
          type = BrickType.multiHit;
          health = 2;
          color = Colors.orange;
        }

        bricks.add(Brick(
          x: padding + c * (brickWidth + padding),
          y: padding + 50 + r * (brickHeight + padding),
          width: brickWidth,
          height: brickHeight,
          color: color,
          type: type,
          health: health,
        ));
      }
    }
  }

  void _update() {
    if (!isPlaying || isPaused || isGameOver) return;

    setState(() {
      // 1. Move Paddle (Handled by GestureDetector, but we clamp here)
      paddle.x = paddle.x.clamp(0, screenSize.width - paddle.width);

      // 2. Move Balls
      for (int i = balls.length - 1; i >= 0; i--) {
        Ball b = balls[i];
        
        if (b.isStuckToPaddle) {
          b.x = paddle.x + paddle.width / 2;
          b.y = paddle.y - b.radius * 2;
          continue;
        }

        b.x += b.dx;
        b.y += b.dy;

        // Wall Collisions
        if (b.x <= 0 || b.x >= screenSize.width) {
          b.dx = -b.dx;
          _spawnWallParticles(b.x <= 0 ? 0 : screenSize.width, b.y, Colors.white);
        }
        if (b.y <= 0) {
          b.dy = -b.dy;
          _spawnWallParticles(b.x, 0, Colors.white);
        }

        // Paddle Collision
        if (b.dy > 0 && 
            b.y + b.radius >= paddle.y && 
            b.y - b.radius <= paddle.y + paddle.height &&
            b.x >= paddle.x && 
            b.x <= paddle.x + paddle.width) {
          
          // Calculate angle based on hit position
          double hitPoint = b.x - (paddle.x + paddle.width / 2);
          double normalizedHit = hitPoint / (paddle.width / 2);
          
          b.dx = normalizedHit * 6.0; // Curve effect
          b.dy = -b.dy.abs(); // Always bounce up
          b.speed += 0.1; // Adaptive speed
          
          // Sound or Haptic could go here
        }

        // Brick Collision
        for (int j = bricks.length - 1; j >= 0; j--) {
          Brick brick = bricks[j];
          if (brick.isDead) continue;

          if (b.x >= brick.x && b.x <= brick.x + brick.width &&
              b.y >= brick.y && b.y <= brick.y + brick.height) {
            
            // Simple collision response (reverse Y usually)
            // A more robust one would check overlap depth
            b.dy = -b.dy;
            
            _hitBrick(brick);
            break; // Only hit one brick per frame per ball to prevent tunneling issues
          }
        }

        // Death
        if (b.y > screenSize.height) {
          balls.removeAt(i);
        }
      }

      // 3. Check Lives
      if (balls.isEmpty) {
        lives--;
        if (lives <= 0) {
          isGameOver = true;
          _controller.stop();
        } else {
          _resetBall();
          isPlaying = false;
          _controller.stop();
        }
      }

      // 4. Move PowerUps
      for (int i = powerUps.length - 1; i >= 0; i--) {
        PowerUp p = powerUps[i];
        p.y += 3.0;
        
        // Collection
        if (p.y + p.size >= paddle.y && 
            p.y <= paddle.y + paddle.height &&
            p.x >= paddle.x && 
            p.x <= paddle.x + paddle.width) {
          _activatePowerUp(p.type);
          powerUps.removeAt(i);
        } else if (p.y > screenSize.height) {
          powerUps.removeAt(i);
        }
      }

      // 5. Update Particles
      for (int i = particles.length - 1; i >= 0; i--) {
        particles[i].update();
        if (particles[i].life <= 0) particles.removeAt(i);
      }

      // 6. Level Complete
      if (bricks.every((b) => b.isDead)) {
        level++;
        difficultyMultiplier += 0.1;
        _buildLevel(level);
        _resetBall();
        isPlaying = false;
        _controller.stop();
      }
    });
  }

  void _hitBrick(Brick brick) {
    brick.health--;
    score += 10 * level;
    
    // Spawn Particles
    _spawnExplosion(brick.x + brick.width/2, brick.y + brick.height/2, brick.color);

    if (brick.health <= 0) {
      brick.isDead = true;
      
      // Explosion Logic
      if (brick.type == BrickType.explosive) {
        _explodeRadius(brick);
      }

      // PowerUp Drop Chance
      if (math.Random().nextDouble() < 0.15) {
        PowerUpType pType = PowerUpType.values[math.Random().nextInt(PowerUpType.values.length)];
        powerUps.add(PowerUp(
          x: brick.x + brick.width / 2,
          y: brick.y + brick.height / 2,
          type: pType,
        ));
      }
    }
  }

  void _explodeRadius(Brick centerBrick) {
    // Destroy neighbors
    for (var b in bricks) {
      if (b.isDead) continue;
      double dist = math.sqrt(math.pow(b.x - centerBrick.x, 2) + math.pow(b.y - centerBrick.y, 2));
      if (dist < 100) {
        b.health = 0;
        b.isDead = true;
        score += 5;
        _spawnExplosion(b.x + b.width/2, b.y + b.height/2, Colors.orange);
      }
    }
    // Camera shake could go here
  }

  void _activatePowerUp(PowerUpType type) {
    switch (type) {
      case PowerUpType.expandPaddle:
        setState(() => paddle.width = (paddle.width * 1.5).clamp(50.0, 200.0));
        Timer(const Duration(seconds: 10), () => setState(() => paddle.width = 100));
        break;
      case PowerUpType.multiBall:
        if (balls.isNotEmpty) {
          Ball b = balls.first;
          balls.add(Ball(x: b.x, y: b.y, dx: -b.dx, dy: b.dy, speed: b.speed, color: Colors.yellow));
          balls.add(Ball(x: b.x, y: b.y, dx: b.dx * 0.5, dy: b.dy * 1.2, speed: b.speed, color: Colors.yellow));
        }
        break;
      case PowerUpType.laser:
        // Implement laser logic
        break;
      case PowerUpType.extraLife:
        lives++;
        break;
    }
  }

  void _spawnExplosion(double x, double y, Color color) {
    for (int i = 0; i < 10; i++) {
      particles.add(Particle(
        x: x,
        y: y,
        dx: (math.Random().nextDouble() - 0.5) * 5,
        dy: (math.Random().nextDouble() - 0.5) * 5,
        color: color,
      ));
    }
  }

  void _spawnWallParticles(double x, double y, Color color) {
    for (int i = 0; i < 5; i++) {
      particles.add(Particle(
        x: x,
        y: y,
        dx: (math.Random().nextDouble() - 0.5) * 3,
        dy: (math.Random().nextDouble() - 0.5) * 3,
        color: color,
      ));
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (isGameOver) return;
    setState(() {
      paddle.x += details.delta.dx;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Initialize game on first build with size
    if (screenSize == Size.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initGame(MediaQuery.of(context).size);
        setState(() {});
      });
    }

    return Scaffold(
      body: GestureDetector(
        onPanUpdate: _onPanUpdate,
        onTap: () {
          if (isGameOver) {
            _initGame(screenSize);
          } else if (!isPlaying) {
            _launchBall();
          }
        },
        child: Stack(
          children: [
            // 1. Background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
                ),
              ),
            ),

            // 2. Game Painter (High Performance)
            CustomPaint(
              size: Size.infinite,
              painter: GamePainter(
                paddle: paddle,
                balls: balls,
                bricks: bricks,
                powerUps: powerUps,
                particles: particles,
              ),
            ),

            // 3. UI Overlay
            Positioned(
              top: 40,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SCORE: $score', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                      Text('LEVEL: $level', style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Courier')),
                    ],
                  ),
                  Row(
                    children: List.generate(lives, (index) => const Icon(Icons.favorite, color: Colors.red)),
                  )
                ],
              ),
            ),

            // 4. Start / Game Over Screens
            if (!isPlaying && !isGameOver)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('TAP TO START', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    const SizedBox(height: 10),
                    Text('Drag to move paddle', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                  ],
                ),
              ),

            if (isGameOver)
              Container(
                color: Colors.black87,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('GAME OVER', style: TextStyle(color: Colors.red, fontSize: 50, fontWeight: FontWeight.bold)),
                      Text('Final Score: $score', style: const TextStyle(color: Colors.white, fontSize: 24)),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: () => _initGame(screenSize),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                        child: const Text('RETRY', style: TextStyle(fontSize: 20, color: Colors.black)),
                      )
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Game Entities ---

class Paddle {
  double x, y, width, height;
  Color color;
  Paddle({required this.x, required this.y, required this.width, required this.height, required this.color});
}

class Ball {
  double x, y, dx, dy, speed;
  double radius = 8;
  Color color;
  bool isStuckToPaddle;
  Ball({required this.x, required this.y, required this.dx, required this.dy, required this.speed, required this.color, this.isStuckToPaddle = false});
}

enum BrickType { normal, hard, explosive, multiHit }

class Brick {
  double x, y, width, height;
  Color color;
  BrickType type;
  int health;
  bool isDead = false;
  Brick({required this.x, required this.y, required this.width, required this.height, required this.color, this.type = BrickType.normal, this.health = 1});
}

enum PowerUpType { expandPaddle, multiBall, laser, extraLife }

class PowerUp {
  double x, y;
  double size = 20;
  PowerUpType type;
  PowerUp({required this.x, required this.y, required this.type});
}

class Particle {
  double x, y, dx, dy;
  Color color;
  double life = 1.0;
  Particle({required this.x, required this.y, required this.dx, required this.dy, required this.color});

  void update() {
    x += dx;
    y += dy;
    life -= 0.02;
  }
}

// --- Custom Painter for High Performance Rendering ---

class GamePainter extends CustomPainter {
  final Paddle paddle;
  final List<Ball> balls;
  final List<Brick> bricks;
  final List<PowerUp> powerUps;
  final List<Particle> particles;

  GamePainter({required this.paddle, required this.balls, required this.bricks, required this.powerUps, required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Draw Bricks
    for (var brick in bricks) {
      if (brick.isDead) continue;
      
      paint.color = brick.color;
      
      // Add glow/shadow for "Pro" look
      if (brick.type == BrickType.explosive) {
        paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 5);
      } else {
        paint.maskFilter = null;
      }

      RRect rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(brick.x, brick.y, brick.width, brick.height),
        const Radius.circular(4),
      );
      canvas.drawRRect(rrect, paint);

      // Draw cracks for damaged bricks
      if (brick.type == BrickType.hard && brick.health < 3) {
        paint.color = Colors.black26;
        paint.strokeWidth = 2;
        canvas.drawLine(Offset(brick.x + 5, brick.y + 5), Offset(brick.x + brick.width - 5, brick.y + brick.height - 5), paint);
        paint.style = PaintingStyle.fill; // reset
      }
    }
    paint.maskFilter = null; // Reset mask

    // Draw Paddle
    paint.color = paddle.color;
    // Gradient for paddle
    paint.shader = LinearGradient(
      colors: [paddle.color.withOpacity(0.7), paddle.color],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(Rect.fromLTWH(paddle.x, paddle.y, paddle.width, paddle.height));
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(paddle.x, paddle.y, paddle.width, paddle.height),
        const Radius.circular(10),
      ),
      paint,
    );
    paint.shader = null;

    // Draw Balls
    for (var ball in balls) {
      paint.color = ball.color;
      // Glow effect
      paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(ball.x, ball.y), ball.radius, paint);
      paint.maskFilter = null;
      // Core
      paint.color = Colors.white;
      canvas.drawCircle(Offset(ball.x, ball.y), ball.radius * 0.7, paint);
    }

    // Draw PowerUps
    for (var p in powerUps) {
      switch (p.type) {
        case PowerUpType.expandPaddle: paint.color = Colors.blue; break;
        case PowerUpType.multiBall: paint.color = Colors.yellow; break;
        case PowerUpType.laser: paint.color = Colors.red; break;
        case PowerUpType.extraLife: paint.color = Colors.green; break;
      }
      canvas.drawCircle(Offset(p.x, p.y), p.size / 2, paint);
      // Icon
      TextSpan span = TextSpan(
        text: p.type == PowerUpType.extraLife ? '+' : '?',
        style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
      );
      TextPainter tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(p.x - tp.width/2, p.y - tp.height/2));
    }

    // Draw Particles
    for (var p in particles) {
      paint.color = p.color.withOpacity(p.life.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(p.x, p.y), 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
