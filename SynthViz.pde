import processing.serial.*;
import ddf.minim.*;

Minim minim;
AudioInput in;

Serial port;
byte[] buf = new byte[26];

int waveform, drumMode, seqMode;
int atkMs, relMs;
int[] vBtn    = {-1, -1};
int[] vEnv    = {  0,   0};
int[] vFlags  = {  0,   0};
int   subBtn  = -1, subEnv = 0, subFlags = 0;
int   drumPat = 0;
int   sideDuck = 0;

// монотонные счётчики — ловим приращение
int  lastNote = 0, lastKick = 0, lastSnare = 0, lastHihat = 0;
float notePulse = 0, kickPulse = 0, snarePulse = 0, hihatPulse = 0;
float duckLevel = 0;     // сглаженный

PShader plasma;

PFont myFont; 
PFont myFontBig;

void setup() {
  size(1280, 720, P3D);
  pixelDensity(1);
  
  myFont = loadFont("JetBrainsMono-Regular-20.vlw"); 
  myFontBig = loadFont("JetBrainsMono-Regular-32.vlw");
  
  port = new Serial(this, "COM3", 115200);
  port.buffer(26);

  plasma = loadShader("plasma.glsl");
  
  
  // Инициализируем Minim и получаем доступ к линейному входу
  minim = new Minim(this);
  // getLineIn() по умолчанию использует текущий источник записи в системе
  // (обычно это микрофон или линейный вход)
  in = minim.getLineIn(Minim.STEREO, 512);
  in.enableMonitoring();   // ← вот этого не хватает
}

void stop() {
  in.close();
  minim.stop();
  super.stop();
}

int packetIndex = 0;
boolean syncFound = false;

void draw() {
  // Читаем побайтово, чтобы не терять синхронизацию
  while (port.available() > 0) {
    int b = port.read();
    
    if (!syncFound) {
      if (b == 0xAA) { // Нашли начало пакета
        buf[0] = (byte)b;
        packetIndex = 1;
        syncFound = true;
      }
    } else {
      buf[packetIndex] = (byte)b;
      packetIndex++;
      if (packetIndex == 26) { // Собрали все 26 байт
        parsePacket();
        syncFound = false; // Ждём следующий пакет
      }
    }
  }
  
  updatePulses();
  render();
}

void parsePacket() {
  // xor check
  int cs = 0;
  for (int i = 0; i < 25; i++) cs ^= (buf[i] & 0xFF);
  if (cs != (buf[25] & 0xFF)) return;

  waveform  = buf[1] & 0xFF;
  drumMode  = buf[2] & 0xFF;
  seqMode   = buf[3] & 0xFF;
  atkMs     = (buf[4] & 0xFF) | ((buf[5] & 0xFF) << 8);
  relMs     = (buf[6] & 0xFF) | ((buf[7] & 0xFF) << 8);

  vFlags[0] = (buf[8]  & 0xFF) >> 6;  vBtn[0] = (buf[8] & 0x80) != 0 ? ((buf[8]  & 0x0F)) : -1;  vEnv[0] = buf[9]  & 0xFF;
  vFlags[1] = (buf[10] & 0xFF) >> 6;  vBtn[1] = (buf[10] & 0x80) != 0 ? ((buf[10] & 0x0F)) : -1; vEnv[1] = buf[11] & 0xFF;
  subFlags  = (buf[12] & 0xFF) >> 6;  subBtn  = (buf[12] & 0x80) != 0 ? ((buf[12] & 0x0F)) : -1;  subEnv  = buf[13] & 0xFF;

  int kickNow  = (buf[14] & 0xFF) | ((buf[15] & 0xFF) << 8);
  int snareNow = (buf[16] & 0xFF) | ((buf[17] & 0xFF) << 8);
  int hihatNow = (buf[18] & 0xFF) | ((buf[19] & 0xFF) << 8);
  drumPat   = buf[20] & 0xFF;
  sideDuck  = (buf[21] & 0xFF) | ((buf[22] & 0xFF) << 8);
  int noteNow = (buf[23] & 0xFF) | ((buf[24] & 0xFF) << 8);

  if (kickNow  != lastKick ) { kickPulse  = 1.0; lastKick  = kickNow ; }
  if (snareNow != lastSnare) { snarePulse = 1.0; lastSnare = snareNow; }
  if (hihatNow != lastHihat) { hihatPulse = 1.0; lastHihat = hihatNow; }
  if (noteNow  != lastNote ) { notePulse  = 1.0; lastNote  = noteNow ; }
}

void updatePulses() {
  float decay = 0.15;
  kickPulse  = max(0, kickPulse  - decay);
  snarePulse = max(0, snarePulse - decay);
  hihatPulse = max(0, hihatPulse - decay);
  notePulse  = max(0, notePulse  - decay);
  duckLevel  = lerp(duckLevel, sideDuck / 65535.0, 0.3);
}

void render() {
  plasma.set("u_time",  millis() / 1000.0);
  plasma.set("u_wave",  waveform);
  plasma.set("u_kick",  kickPulse);
  plasma.set("u_note",  notePulse);
  plasma.set("u_duck",  duckLevel);
  plasma.set("u_res",   (float)width, (float)height);
  shader(plasma);
  rect(0, 0, width, height);
  resetShader();

  drawHud();
  drawNotePads();
}

void drawHud() {
  // Полупрозрачные плашки под текст (чтобы не сливалось с плазмой)
  noStroke();
  fill(0, 150); // черный, прозрачность 150 из 255
  rect(10, 10, 240, 160, 10); // верхний левый угол
  
  fill(255);
  textFont(myFont);
  textAlign(LEFT, TOP);

  text("ATTACK:  " + atkMs + " ms", 25, 25);
  text("RELEASE: " + relMs + " ms", 25, 55);
  text("WAVE:    " + (waveform == 0 ? "SINE" : waveform == 1 ? "SAW" : "SQUARE"), 25, 85);
  text("MODE:    " + (drumMode == 1 ? "DRUM" : "SYNTH"), 25, 115);
  
  // Статус секвенсора
  if (seqMode == 0) fill(200);
  else if (seqMode == 1) fill(255, 50, 50); // REC красный
  else fill(50, 255, 100); // PLAY зелёный
  text("SEQ:     " + (seqMode == 0 ? "IDLE" : seqMode == 1 ? "RECORDING" : "PLAYING"), 25, 145);

  // Индикаторы барабанов (внизу справа)
  noStroke();
  fill(0, 150);
  rect(width - 180, height - 120, 180, 100, 10);
  
  textFont(myFont);
  textAlign(RIGHT, TOP);
  
  // Kick (вспыхивает красным)
  fill(kickPulse > 0 ? color(255, 50, 50) : color(150));
  text("KICK", width - 100, height - 110);
  fill(255);
  text(nf(kickPulse, 1, 2), width - 30, height - 110);

  // Snare (синим)
  fill(snarePulse > 0 ? color(50, 150, 255) : color(150));
  text("SNARE", width - 100, height - 80);
  fill(255);
  text(nf(snarePulse, 1, 2), width - 30, height - 80);

  // Hihat (жёлтым)
  fill(hihatPulse > 0 ? color(255, 255, 50) : color(150));
  text("HIHAT", width - 100, height - 50);
  fill(255);
  text(nf(hihatPulse, 1, 2), width - 30, height - 50);

  // Красная/зелёная рамка при записи/плее
  if (seqMode == 1 || seqMode == 2) {
    noFill();
    stroke(seqMode == 1 ? color(255, 40, 40) : color(50, 255, 100));
    strokeWeight(4);
    rect(2, 2, width - 4, height - 4, 10);
  }
}

void drawNotePads() {
  // Ноты теперь в виде линии внизу экрана
  int numNotes = 5;
  float padSize = 80;
  float spacing = 100;
  float startX = width/2 - (numNotes - 1) * spacing / 2;
  float y = height - 120; // Отступ от низа экрана

  for (int i = 0; i < numNotes; i++) {
    float x = startX + i * spacing;
    
    boolean held = false;
    int     env  = 0;
    
    // Проверяем, играет ли нота в голосах
    for (int v = 0; v < 2; v++) {
      if (vBtn[v] == i) { held = true; env = max(env, vEnv[v]); }
    }
    // Проверяем саббас
    if (subBtn == i) { held = true; env = max(env, subEnv); }

    if (held) {
      // Свечение (рисуем несколько кругов с уменьшающейся прозрачностью)
      noStroke();
      
      // Сам кружок
      fill(255, 200, 40);
      ellipse(x, y, padSize, padSize);
      
      // Отрисовка номера ноты (черным)
      fill(0);
      textFont(myFontBig);
      textAlign(CENTER, CENTER);
      text("" + (i + 1), x, y - 2);
      
    } else {
      // Неактивная нота (полупрозрачная)
      fill(50, 150);
      noStroke();
      ellipse(x, y, padSize, padSize);
      
      // Окантовка неактивной ноты
      noFill();
      stroke(100, 150);
      strokeWeight(2);
      ellipse(x, y, padSize, padSize);
      
      // Номер
      fill(150);
      textFont(myFontBig);
      textAlign(CENTER, CENTER);
      text("" + (i + 1), x, y - 2);
    }
  }
}
