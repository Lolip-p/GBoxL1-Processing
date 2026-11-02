#ifdef GL_ES
precision highp float;
#endif

uniform float u_time;
uniform int   u_wave;
uniform float u_kick;
uniform float u_note;
uniform float u_duck;
uniform vec2  u_res;

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_res) / u_res.y;
  float d = length(p);

  // базовый плазма-паттерн
  float plasma  = sin(p.x * 6.0 + u_time) * sin(p.y * 6.0 + u_time * 1.3);
  plasma       += sin((p.x + p.y) * 8.0 - u_time * 1.7) * 0.6;
  plasma       += sin(d * 12.0 - u_time * 2.5) * 0.4;
  plasma        = plasma * 0.5 + 0.5;

  // цвет от формы волны
  vec3 col;
  if      (u_wave == 0) col = vec3(0.20, 0.40, 1.00);   // sine   -> синий
  else if (u_wave == 1) col = vec3(1.00, 0.55, 0.10);   // saw    -> оранжевый
  else                  col = vec3(0.20, 1.00, 0.45);   // square -> зелёный

  // кик — красное свечение по центру
  col += vec3(1.0, 0.35, 0.15) * exp(-d * 3.0) * u_kick * 1.2;

  // нота — общий буст яркости
  col *= (0.75 + 0.5 * u_note);

  // sidechain — виньетка пульсирует
  col *= 1.0 - d * (0.35 + 0.25 * u_duck);

  gl_FragColor = vec4(col * plasma, 1.0);
}