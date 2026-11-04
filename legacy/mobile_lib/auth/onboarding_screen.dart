import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/comein_widgets.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onContinue;
  const OnboardingScreen({super.key, required this.onContinue});
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}
class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController motion;
  int page = 0;
  static const headings = ['A place to belong.', 'Living feels lighter.', 'Everything, together.'];
  static const subtitles = [
    'From your hometown to your new beginning. Discover the comfort of community living.',
    'Rent, rooms, maintenance and everyday updates—right at your fingertips.',
    'Owners and residents, connected in one welcoming place.',
  ];
  @override void initState() { super.initState(); motion = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat(); }
  @override void dispose() { motion.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(23, 20, 23, 25), child: Column(children: [
    Row(children: [const BrandMark(size: 40), const Spacer(), TextButton(onPressed: widget.onContinue, child: const Text('Skip'))]),
    const Spacer(),
    AspectRatio(aspectRatio: 1.05, child: AnimatedBuilder(animation: motion, builder: (context, _) => CustomPaint(painter: _JourneyPainter(t: motion.value, scene: page)))),
    const Spacer(),
    AnimatedSwitcher(duration: const Duration(milliseconds: 320), child: Column(key: ValueKey(page), children: [
      Text(headings[page], textAlign: TextAlign.center, style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900, color: plum)),
      const SizedBox(height: 12), Text(subtitles[page], textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.45, fontSize: 15)),
    ])),
    const SizedBox(height: 28), Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) => AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.all(4), height: 7, width: i == page ? 28 : 8, decoration: BoxDecoration(color: i == page ? plum : lavender.withValues(alpha: .35), borderRadius: BorderRadius.circular(8))))),
    const SizedBox(height: 15), SizedBox(width: double.infinity, child: FilledButton(onPressed: () => page == 2 ? widget.onContinue() : setState(() => page++), child: Text(page == 2 ? 'Get started' : 'Next  →'))),
  ]))));
}

class _JourneyPainter extends CustomPainter {
  final double t;
  final int scene;
  _JourneyPainter({required this.t, required this.scene});
  @override void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()..isAntiAlias = true;
    void rect(Rect r, Color c, [double radius = 0]) { paint.color = c; canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), paint); }
    void circle(Offset p, double r, Color c) {paint.color = c; canvas.drawCircle(p, r, paint);}
    final haze = Paint()..color = blush.withValues(alpha: .42);
    canvas.drawOval(Rect.fromLTWH(w*.12, h*.17, w*.77, h*.67), haze);
    // Hometown house.
    rect(Rect.fromLTWH(w*.05, h*.49, w*.24, h*.30), const Color(0xFFD9AFB8), 11);
    final roof = Path()..moveTo(w*.02,h*.51)..lineTo(w*.17,h*.37)..lineTo(w*.32,h*.51)..close();
    canvas.drawPath(roof, Paint()..color= const Color(0xFF926C92));
    rect(Rect.fromLTWH(w*.13,h*.63,w*.07,h*.16),cream,6);
    // City towers and windows.
    rect(Rect.fromLTWH(w*.58,h*.30,w*.24,h*.47),const Color(0xFFA783BC),15);
    rect(Rect.fromLTWH(w*.79,h*.42,w*.17,h*.35),const Color(0xFFE8BCC0),12);
    for (var i=0;i<3;i++) {for (var j=0;j<2;j++) {rect(Rect.fromLTWH(w*(.62+j*.10),h*(.38+i*.11),w*.045,h*.055),const Color(0xFFFFF3E3),5);}}
    for (var i=0;i<3;i++) {rect(Rect.fromLTWH(w*(.835+(i%2)*.065),h*(.49+(i~/2)*.10),w*.038,h*.05),cream,4);}
    rect(Rect.fromLTWH(w*.60,h*.265,w*.21,h*.063),plum,8);
    final p = TextPainter(text: const TextSpan(text:'PG · STAY',style:TextStyle(color:Colors.white,fontSize:10,fontWeight:FontWeight.w900)),textDirection:TextDirection.ltr)..layout();
    p.paint(canvas, Offset(w*.625,h*.278));
    rect(Rect.fromLTWH(0,h*.80,w,h*.027),const Color(0xFFCFB9CE),8);
    // Four character silhouettes in 2-D editorial style, heading forward into the city.
    for (int i=0;i<4;i++) {
      final gait = math.sin(2*math.pi*(t*3+i*.25));
      final progress = scene==0 ? .04 + (t*.11) : .1;
      final x=w*(.31+i*.103+progress), y=h*(.695+(i%2)*.025), scale=1.0-(progress*.18);
      canvas.save();canvas.translate(x,y);canvas.scale(scale);
      final shirt=[const Color(0xFF7A4576),const Color(0xFFB55E81),const Color(0xFF568E94),const Color(0xFFD6AE68)][i];
      circle(const Offset(0,-33),10,const Color(0xFFE5B097));
      rect(const Rect.fromLTWH(-10,-48,20,9),i.isEven?plum:const Color(0xFF4A2D43),8);
      rect(const Rect.fromLTWH(-12,-24,24,30),shirt,7);
      paint.color = const Color(0xFF453247); paint.strokeWidth=5;paint.strokeCap=StrokeCap.round;
      canvas.drawLine(const Offset(-6,5),Offset(-8+gait*3,19),paint);
      canvas.drawLine(const Offset(6,5),Offset(8-gait*3,19),paint);
      paint.color=const Color(0xFFE3B0A5);paint.strokeWidth=4;
      canvas.drawLine(const Offset(-11,-19),const Offset(-18,-6),paint);
      canvas.drawLine(const Offset(11,-19),const Offset(17,-6),paint);
      rect(const Rect.fromLTWH(-17,-19,6,20),const Color(0xFF775777),4);
      // Rolling suitcase.
      final luggageX= i.isEven ? -24.0 : 23.0;
      paint.color=plum;paint.strokeWidth=1.5;
      canvas.drawLine(Offset(luggageX,y*0-13),Offset(luggageX,y*0-20),paint);
      rect(Rect.fromLTWH(luggageX-6,-12,12,22),[lavender,blush,const Color(0xFFC7AD83),const Color(0xFF9877B1)][i],3);
      circle(Offset(luggageX-3,11),1.8,plum);circle(Offset(luggageX+3,11),1.8,plum);
      canvas.restore();
    }
  }
  @override bool shouldRepaint(covariant _JourneyPainter old) => old.t != t || old.scene != scene;
}
