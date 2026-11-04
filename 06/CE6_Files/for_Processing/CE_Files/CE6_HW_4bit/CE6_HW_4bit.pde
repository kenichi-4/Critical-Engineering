import processing.serial.*;
import ddf.minim.*;

Serial port;
Minim minim;

// ===== 通信速度設定 =====
final int BAUD_RATE = 115200;

// ===== サウンドファイル =====
String soundFile = "/Users/fukushimakenichi/2026/クリティカル/5/CE_Files/Sounds/StratoS.wav";

// ===== 処理設定 =====
final int DOWNSAMPLE_FACTOR = 5;   // 44100 Hz → 8820 Hz
final int BIT_DEPTH = 4;

float inputRate;
float SAMPLE_RATE;

LowPassFilter lowPass;
DownSampler downSampler;
BitCrusher bitCrusher;

float[] monoSamples;
int srcIndex = 0;

// 1回にまとめて送るサンプル数
final int BLOCK_SIZE = 64;

// ===== 送受信確認用 =====
int MAX_SAMPLES;
int[] sentData;

int sendIndex = 0;
int receiveIndex = 0;

// エラー情報
int errorCount = 0;
int maxError = 0;

// 描画用
final int DISPLAY_SAMPLES = 200;
float[] receivedWave = new float[DISPLAY_SAMPLES];
int displayIndex = 0;

// 処理を停止するためのフラグ
boolean running = true;

// 送信スケジュール用
long nextSendTime;


void setup() {
  pixelDensity(2);
  size(900, 400);

  loadSound();
  if (monoSamples == null) {
    return;
  }

  println("=== Serial ports ===");
  String[] ports = Serial.list();

  for (int i = 0; i < ports.length; i++) {
    println("[" + i + "] " + ports[i]);
  }

  if (ports.length == 0) {
    println("Serial port not found.");
    exit();
    return;
  }

  // 自分の環境に合わせて変更
  // 例：/dev/cu.usbmodem...
  int portIndex = 2;

  if (portIndex >= ports.length) {
    println("Invalid port index.");
    exit();
    return;
  }

  String portName = ports[portIndex];
  println("Connecting to: " + portName);

  port = new Serial(this, portName, BAUD_RATE);

  // Arduinoのリセット待ち
  delay(2000);
  // Arduino起動時に残っているデータを破棄
  port.clear();

  nextSendTime = System.nanoTime();
  println("Start.");
}

void loadSound() {
  minim = new Minim(this);
  AudioSample sound = minim.loadSample(soundFile, 1024);

  if (sound == null) {
    println("Could not load " + soundFile);
    exit();
    return;
  }

  inputRate = sound.sampleRate();
  SAMPLE_RATE = inputRate / DOWNSAMPLE_FACTOR;

  float[] left = sound.getChannel(AudioSample.LEFT);
  float[] right = sound.getChannel(AudioSample.RIGHT);
  if (right == null || right.length != left.length) {
    right = left;
  }

  monoSamples = new float[left.length];
  for (int i = 0; i < left.length; i++) {
    monoSamples[i] = 0.5 * (left[i] + right[i]);
  }
  sound.close();

  float cutoff = 0.8 * SAMPLE_RATE / 2.0;
  lowPass = new LowPassFilter(cutoff, inputRate);
  downSampler = new DownSampler(DOWNSAMPLE_FACTOR);
  bitCrusher = new BitCrusher(BIT_DEPTH);

  MAX_SAMPLES = monoSamples.length / DOWNSAMPLE_FACTOR + 1;
  sentData = new int[MAX_SAMPLES];

  println("Input rate  : " + inputRate + " Hz");
  println("Output rate : " + SAMPLE_RATE + " Hz");
  println("LPF cutoff  : " + cutoff + " Hz");
}

void draw() {
  background(255);  // 背景色

  // ===== ステータス表示 =====
  fill(0);          // 図形の塗りつぶし色
  textSize(18);     // テキストサイズ

  text("LPF + DS + BC",                        20, 30);
  text("Sample rate : " + SAMPLE_RATE + " Hz", 20, 60);
  text("Baud rate   : " + BAUD_RATE,           20, 90);
  text("Quantize   : 4 bit", 20, 120);

  text("Sent samples : " + sendIndex,    220, 30);
  text("Received     : " + receiveIndex, 220, 60);
  text("Errors       : " + errorCount,   220, 90);
  text("Maximum error: " + maxError,     220, 120);

  // ===== 返送された波形を描画 =====
  pushMatrix();      // 現在の座標系を保存
  translate(0, 300); // 描画の開始位置の指定

  stroke(180);          // 線の色（灰色）
  line(0, 0, width, 0); // 線の描画

  stroke(0, 0, 255);    // 線の色（青）
  noFill();             // 図形を塗りつぶさない

  beginShape(); // vertex で指定した頂点を繋いで作図
  for (int i = 0; i < DISPLAY_SAMPLES; i++) {

    int index = (displayIndex + i) % DISPLAY_SAMPLES;
    float x = map(i, 0, DISPLAY_SAMPLES - 1, 0, width); // 値iの範囲を変換
    float y = map(receivedWave[index], -1.0, 1.0, 100, -100);

    vertex(x, y);
  }
  endShape();
  popMatrix();     // 座標系の復元

  if (running) {
    long now = System.nanoTime();             // 現在時刻

    while (running && now >= nextSendTime) {  // 現在時刻が予定送信時刻を超えたら
      sendBlock();                            // Blockの送信
      nextSendTime += (long)(1.0e9 * BLOCK_SIZE / SAMPLE_RATE); // 次の送信時刻
    }
  }
  if (!running) {     // ファイルの最後に達して止まったら
    fill(255, 0, 0);
    text("Transmission stopped", 20, 160);
  }
}

// LPF → DS → BC を通した次の1サンプルを返す（ファイル終端では NaN）
float nextSample() {
  while (srcIndex < monoSamples.length) {
    float filtered = lowPass.process(monoSamples[srcIndex]);
    srcIndex++;
    if (downSampler.process(filtered)) {
      return bitCrusher.process(downSampler.getSample());
    }
  }
  return Float.NaN;
}

void sendBlock() {
  // 64 samples → 32 bytes
  for (int i = 0; i < BLOCK_SIZE; i += 2) {
    // ==========================================
    // 1個目のサンプル
    // ==========================================
    float sample1 = nextSample();
    // ==========================================
    // 2個目のサンプル
    // ==========================================
    float sample2 = nextSample();

    if (Float.isNaN(sample1) || Float.isNaN(sample2) || sendIndex + 1 >= MAX_SAMPLES) {
      running = false;
      return;
    }

    // ===== -1.0～+1.0 → -8～+7 =====
    int value1 = round(sample1 * 8);
    value1 = constrain(value1, -8, 7);
    int value2 = round(sample2 * 8);
    value2 = constrain(value2, -8, 7);

    // ==========================================
    // 送信値を保存（2乗しない）
    // ==========================================
    sentData[sendIndex] = value1;
    sendIndex++;

    sentData[sendIndex] = value2;
    sendIndex++;

    // ==========================================
    // 4 bit + 4 bit → 1 byte
    // ==========================================
    int packed = ((value1 & 0x0F) << 4) | (value2 & 0x0F);

    // ==========================================
    // 1 byte送信
    // ==========================================
    port.write(packed);
  }
}

void serialEvent(Serial p) {
  while (p.available() > 0) {
    // ======================================
    // 1 byte受信
    // ======================================
    int receivedByte = p.read();

    // ======================================
    // 上位4 bit
    // ======================================
    int sample1 = (receivedByte >> 4) & 0x0F;
    if (sample1 >= 8) {
      sample1 -= 16;
    }

    // ======================================
    // 下位4 bit
    // ======================================
    int sample2 = receivedByte & 0x0F;
    if (sample2 >= 8) {
      sample2 -= 16;
    }

    // ======================================
    // 2 samples処理（比較と波形表示を関数化）
    // ======================================
    processReceivedSample(sample1);
    processReceivedSample(sample2);
  }
}

void processReceivedSample(int receivedSample) {
  // --------------------------------------
  // 送信値と比較
  // --------------------------------------
  if (receiveIndex < sendIndex) {
    int sentSample = sentData[receiveIndex];
    int error = receivedSample - sentSample;

    if (error != 0) {
      errorCount++;

      println(
        "ERROR sample=" + receiveIndex
        + " sent=" + sentSample
        + " received=" + receivedSample
        + " error=" + error
      );
    }
    maxError = max(maxError, abs(error));
  }

  // --------------------------------------
  // 波形表示
  // --------------------------------------
  float normalized = receivedSample / 8.0;
  receivedWave[displayIndex] = constrain(normalized, -1.0, 1.0);
  displayIndex++;

  if (displayIndex >= DISPLAY_SAMPLES) {
    displayIndex = 0;
  }
  receiveIndex++;
}

void keyPressed() {
  // Sキー：送信開始／再開
  if (key == 's' || key == 'S') {
    running = true;
    nextSendTime = System.nanoTime();
  }

  // Cキー：カウンタとエラー情報をクリアして最初から
  if (key == 'c' || key == 'C') {
    sendIndex = 0;
    receiveIndex = 0;

    errorCount = 0;
    maxError = 0;

    displayIndex = 0;

    for (int i = 0; i < DISPLAY_SAMPLES; i++) {
      receivedWave[i] = 0;
    }
    port.clear();

    srcIndex = 0;
    lowPass.reset();
    downSampler.reset();
  }
}

// ============================================================
// Low Pass Filter
// ============================================================
class LowPassFilter {
  float alpha;
  float previous = 0.0;

  LowPassFilter(float cutoff, float sampleRate) {
    float ts = 1.0 / sampleRate;
    float tau = 1.0 / (2.0 * PI * cutoff);
    alpha = ts / (tau + ts);
  }

  float process(float input) {
    previous = previous + alpha * (input - previous);
    return previous;
  }

  void reset() {
    previous = 0;
  }
}

// ============================================================
// DownSampler
// ============================================================
class DownSampler {
  int factor;
  int counter = 0;
  float lastSample = 0;

  DownSampler(int downsampleFactor) {
    factor = downsampleFactor;
  }

  boolean process(float input) {
    counter++;

    if (counter >= factor) {
      counter = 0;
      lastSample = input;
      return true;
    }
    return false;
  }

  float getSample() {
    return lastSample;
  }

  void reset() {
    counter = 0;
    lastSample = 0;
  }
}

// ============================================================
// Bit Crusher
// ============================================================
class BitCrusher {
  int bits;
  float step;

  BitCrusher(int bitDepth) {
    bits = bitDepth;
    step = 2.0 / pow(2, bits);
  }

  float process(float input) {
    input = constrain(input, -1.0, 1.0);
    float quantized = round(input / step) * step;
    quantized = constrain(quantized, -1.0, 1.0);
    return quantized;
  }
}

void stop() {
  running = false;
  if (port != null) {
    port.stop();
  }
  if (minim != null) {
    minim.stop();
  }
  super.stop();
}
