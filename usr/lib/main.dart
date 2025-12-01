import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const TarzanGameApp());
}

class TarzanGameApp extends StatelessWidget {
  const TarzanGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jump Tarzan Clone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        fontFamily: 'Courier', // Arcade style font feel
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

class _GameScreenState extends State<GameScreen> {
  // Game Settings
  static const double gravity = 0.8;
  static const double jumpStrength = -15.0;
  static const double gameSpeed = 5.0;
  
  // Player State
  double tarzanY = 0;
  double tarzanVelocity = 0;
  bool isJumping = false;
  double tarzanX = 50; // Fixed horizontal position
  double tarzanSize = 50;

  // Environment State
  double groundHeight = 0; // Will be set in build
  List<Obstacle> obstacles = [];
  Timer? gameLoopTimer;
  int score = 0;
  bool isGameOver = false;
  bool isPlaying = false;

  @override
  void dispose() {
    gameLoopTimer?.cancel();
    super.dispose();
  }

  void startGame() {
    setState(() {
      tarzanY = 0; // Reset position (relative to ground)
      tarzanVelocity = 0;
      obstacles.clear();
      score = 0;
      isGameOver = false;
      isPlaying = true;
      isJumping = false;
    });

    // Start the game loop (60 FPS approx)
    gameLoopTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      updateGame();
    });
  }

  void jump() {
    if (!isPlaying || isGameOver) return;
    
    // Allow jump only if on ground (or double jump logic if desired)
    if (tarzanY <= 0) {
      setState(() {
        tarzanVelocity = jumpStrength;
        isJumping = true;
      });
    }
  }

  void updateGame() {
    if (isGameOver) {
      gameLoopTimer?.cancel();
      return;
    }

    setState(() {
      // 1. Physics (Gravity)
      tarzanVelocity += gravity;
      tarzanY -= tarzanVelocity;

      // Ground collision
      if (tarzanY <= 0) {
        tarzanY = 0;
        tarzanVelocity = 0;
        isJumping = false;
      }

      // 2. Obstacle Spawning
      if (Random().nextInt(100) < 2 && (obstacles.isEmpty || obstacles.last.x < MediaQuery.of(context).size.width - 200)) {
        obstacles.add(Obstacle(
          x: MediaQuery.of(context).size.width,
          width: 40 + Random().nextInt(40).toDouble(),
          height: 40 + Random().nextInt(40).toDouble(),
          type: Random().nextBool() ? ObstacleType.rock : ObstacleType.bush,
        ));
      }

      // 3. Move Obstacles & Collision Detection
      for (int i = obstacles.length - 1; i >= 0; i--) {
        obstacles[i].x -= gameSpeed;

        // Collision Check (AABB)
        // Tarzan Rect
        // Since tarzanY is distance FROM BOTTOM, we need to convert for collision logic if needed,
        // but simple overlap check works:
        // Tarzan X range: [tarzanX, tarzanX + tarzanSize]
        // Obstacle X range: [obs.x, obs.x + obs.width]
        
        bool collisionX = (tarzanX < obstacles[i].x + obstacles[i].width) && 
                          (tarzanX + tarzanSize > obstacles[i].x);
        
        // Tarzan Y is from bottom 0. Obstacle height is from bottom 0.
        bool collisionY = tarzanY < obstacles[i].height; 

        if (collisionX && collisionY) {
          gameOver();
        }

        // Remove off-screen obstacles and increase score
        if (obstacles[i].x < -100) {
          obstacles.removeAt(i);
          score++;
        }
      }
    });
  }

  void gameOver() {
    setState(() {
      isGameOver = true;
      isPlaying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Screen dimensions
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final groundLevel = screenHeight * 0.2; // Ground takes up bottom 20%

    return Scaffold(
      body: GestureDetector(
        onTap: () {
          if (isGameOver) {
            startGame();
          } else if (!isPlaying) {
            startGame();
          } else {
            jump();
          }
        },
        child: Stack(
          children: [
            // 1. Background (Jungle Sky)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF87CEEB), Color(0xFFE0F7FA)],
                ),
              ),
            ),

            // 2. Distant Trees (Parallax effect simulation - static for now)
            Positioned(
              bottom: groundLevel,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(5, (index) => Icon(Icons.forest, size: 100, color: Colors.green[800]!.withOpacity(0.5))),
              ),
            ),

            // 3. Ground
            Positioned(
              bottom: 0,
              height: groundLevel,
              width: screenWidth,
              child: Container(
                color: const Color(0xFF5D4037), // Brown earth
                child: Column(
                  children: [
                    Container(height: 20, color: const Color(0xFF388E3C)), // Grass top
                  ],
                ),
              ),
            ),

            // 4. Obstacles
            ...obstacles.map((obs) {
              return Positioned(
                bottom: groundLevel, // Sit on top of ground
                left: obs.x,
                child: Container(
                  width: obs.width,
                  height: obs.height,
                  decoration: BoxDecoration(
                    color: obs.type == ObstacleType.rock ? Colors.grey[700] : Colors.green[900],
                    borderRadius: BorderRadius.circular(obs.type == ObstacleType.rock ? 10 : 20),
                  ),
                  child: Icon(
                    obs.type == ObstacleType.rock ? Icons.landscape : Icons.grass,
                    color: Colors.white.withOpacity(0.3),
                    size: 30,
                  ),
                ),
              );
            }),

            // 5. Player (Tarzan)
            Positioned(
              bottom: groundLevel + tarzanY,
              left: tarzanX,
              child: Container(
                width: tarzanSize,
                height: tarzanSize,
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.person, color: Colors.white, size: 30),
                ),
              ),
            ),

            // 6. UI: Score
            Positioned(
              top: 50,
              right: 20,
              child: Text(
                'Score: $score',
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),

            // 7. UI: Start / Game Over Screen
            if (!isPlaying)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isGameOver ? 'GAME OVER' : 'JUMP TARZAN',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: isGameOver ? Colors.red : Colors.yellow,
                          shadows: const [Shadow(blurRadius: 10, color: Colors.black)],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isGameOver ? 'Tap to Restart' : 'Tap to Start',
                        style: const TextStyle(fontSize: 24, color: Colors.white),
                      ),
                      if (isGameOver)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text('Final Score: $score', style: const TextStyle(color: Colors.white, fontSize: 20)),
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

enum ObstacleType { rock, bush }

class Obstacle {
  double x;
  final double width;
  final double height;
  final ObstacleType type;

  Obstacle({
    required this.x,
    required this.width,
    required this.height,
    required this.type,
  });
}
