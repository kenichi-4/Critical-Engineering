import ddf.minim.*;
import processing.serial.*;
import java.util.concurrent.ArrayBlockingQueue;

// ============================================================
// 動的閾値&リフクラクトリー対応版
// ============================================================
// インスタンス
Minim minim;
AudioPlayer player;
Serial port;
LowPassFilter lowPass;
DownSampler downSampler;
BitCrusher bitCrusher;

// ============================================================
// サウンドファイル（パスを修正してください）
// ============================================================
String soundFile =
  "/Users/fukushimakenichi/2026/クリ/5/CE_Files/Sounds/StratoS.wav";
//  "/Users/fukushimakenichi/2026/クリ/5/CE_Files/Sounds/northside-drive.wav";
//  "/Users/fukushimakenichi/2026/クリ/5/CE_Files/Sounds/techno-trance.wav";
//  "/Users/fukushimakenichi/2026/クリ/5/CE_Files/Sounds/Pattern1.wav";
// ============================================================

// ============================================================
// 基本設定
// ============================================================
final int BAUD_RATE = 115200;
//final int BAUD_RATE = 230400;

// Down Sampling factor
final int DOWNSAMPLE_FACTOR = 2;

// Bit Crusher
final int BIT_DEPTH = 4;
final int BUFFER_SIZE = 1024;

float originalSampleRate;
float outputSampleRate;

// ============================================================
// Serial送信用Queue
// ============================================================
ArrayBlockingQueue<Byte> txQueue =
  new ArrayBlockingQueue<Byte>(2000);

// ============================================================
// 統計情報
// ============================================================
long soundSamples = 0;
long downsampledSamples = 0;
long transmittedSamples = 0;  // transmitted audio samples
long droppedSamples = 0;      // dropped audio samples

// ============================================================
// 4 bit sample packing
// ============================================================
int pendingNibble = 0;
boolean packingPending = false;

// ============================================================
// エネルギー表示
// ============================================================
final int DISPLAY_POINTS = 500;
float[] energyWave = new float[DISPLAY_POINTS];
float[] thresholdWave = new float[DISPLAY_POINTS];
boolean[] beatWave = new boolean[DISPLAY_POINTS];
int displayIndex = 0;
int displayCount = 0;

// ============================================================
// スケーリング
// ============================================================
float maxValue = 1.0;

// ============================================================
// Serial送信スレッド
// ============================================================
volatile boolean running = true;
Thread serialThread;

// ============================================================
// setup
// ============================================================
void setup() {
  pixelDensity(2);
  size(1000, 600);

  // ----------------------------------------------------------
  // Serial
  // ----------------------------------------------------------
  String[] ports =  Serial.list();
  println("=== Serial ports ===");

  for (int i = 0; i < ports.length; i++) {
    println("[" + i + "] " + ports[i]);
  }

  // 環境に応じて変更
  int portIndex = 2;

  port = new Serial(this, ports[portIndex], BAUD_RATE);
  delay(2000);
  port.clear();
  // 改行までを1データとして受信
  port.bufferUntil('\n');

  // ----------------------------------------------------------
  // Minim
  // ----------------------------------------------------------
  minim = new Minim(this);
  player = minim.loadFile(soundFile, BUFFER_SIZE);

  originalSampleRate = player.sampleRate();  // サンプリングレート (Hz)
  outputSampleRate = originalSampleRate / (float)DOWNSAMPLE_FACTOR;
  // ----------------------------------------------------------
  // Audio processing
  // ----------------------------------------------------------
  // 新しいナイキスト周波数
  float nyquist = outputSampleRate / 2.0;
  // 簡易アンチエイリアシング用LPF
  float cutoffFreq = 0.8 * nyquist;

  lowPass = new LowPassFilter(cutoffFreq, originalSampleRate);
  downSampler = new DownSampler(DOWNSAMPLE_FACTOR);
  bitCrusher = new BitCrusher(BIT_DEPTH);

  // ----------------------------------------------------------
  // AudioListener
  // ----------------------------------------------------------
  player.addListener(new MyAudioListener());

  // ----------------------------------------------------------
  // Serial送信スレッド
  // ----------------------------------------------------------
  serialThread = new Thread(new Runnable() {
    public void run() {
      serialSendLoop();
    }
  }
  );

  serialThread.start();

  // ----------------------------------------------------------
  // 4 bit packing state
  // ----------------------------------------------------------
  pendingNibble = 0;
  packingPending = false;

  // ----------------------------------------------------------
  // 再生開始
  // ----------------------------------------------------------
  player.play();
}

// ============================================================
// AudioListener
// ============================================================
class MyAudioListener
  implements AudioListener {
  // ----------------------------------------------------------
  // Stereo input
  // ----------------------------------------------------------
  public void samples(float[] sampL, float[] sampR) {
    if (player == null || !player.isPlaying()) {
      return;
    }
    for (int i = 0; i < sampL.length; i++) {
      // Stereo → Mono
      float sample = 0.5 * (sampL[i] + sampR[i]);
      processSample(sample);
    }
  }

  // ----------------------------------------------------------
  // Mono input
  // ----------------------------------------------------------
  public void samples(float[] samp) {
    if (player == null || !player.isPlaying()) {
      return;
    }
    for (int i = 0; i < samp.length; i++) {
      processSample(samp[i]);
    }
  }
}

// ============================================================
// 1サンプルを処理
// ============================================================
void processSample(float sample) {
  soundSamples++;

  // ----------------------------------------------------------
  // LPF
  // ----------------------------------------------------------
  float filtered = lowPass.process(sample);

  // ----------------------------------------------------------
  // Down Sampling
  // ----------------------------------------------------------
  boolean newSample = downSampler.process(filtered);

  // Down Samplingによって新しいサンプルが生成されなかった場合は
  // Serial送信しない
  if (!newSample) {
    return;
  }

  // ----------------------------------------------------------
  // Down Sampled value
  // ----------------------------------------------------------
  float downsampledSample = downSampler.getSample();
  downsampledSamples++;

  // ----------------------------------------------------------
  // Bit Crusher
  // ----------------------------------------------------------
  int value = bitCrusher.process(downsampledSample);

  // ----------------------------------------------------------
  // 2 samples (4 bit + 4 bit) -> 1 byte
  // 1st sample: upper nibble, 2nd sample: lower nibble
  // ----------------------------------------------------------
  if (!packingPending) {
    pendingNibble = value & 0x0F;
    packingPending = true;
  } else {
    int packed = (pendingNibble << 4) | (value & 0x0F);

    if (!txQueue.offer((byte)packed)) {
      // 1 packed byte contains 2 samples
      droppedSamples += 2;
    }

    packingPending = false;
  }
}

// ============================================================
// Serial送信処理
// ============================================================
void serialSendLoop() {
  while (running) {
    try {
      byte value = txQueue.take();

      port.write(value & 0xFF);
      transmittedSamples += 2;
    }
    catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return;
    }
    catch (RuntimeException e) {
      println("Serial send error: " + e);
      running = false;
      return;
    }
  }
}

// ============================================================
// Arduinoから受信
// ============================================================
void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');

  if (line == null) {
    return;
  }

  line = trim(line);
  // ----------------------------------------------------------
  // energy,threshold,beat
  // ----------------------------------------------------------
  String[] values = split(line, ',');

  if (values.length != 3) {
    return;
  }

  try {
    float energy = Float.parseFloat(values[0]);
    float threshold = Float.parseFloat(values[1]);
    int beat = Integer.parseInt(values[2]);

    if (Float.isNaN(energy) || Float.isInfinite(energy) ||
      Float.isNaN(threshold) || Float.isInfinite(threshold) ||
      (beat != 0 && beat != 1)) {
      return;
    }
    // ------------------------------------------
    // リングバッファ
    // ------------------------------------------
    energyWave[displayIndex] = energy;
    thresholdWave[displayIndex] = threshold;
    beatWave[displayIndex] = (beat == 1);

    // 自動スケール
    maxValue = max(maxValue, max(energy, threshold));
    
    displayIndex++;

    if (displayIndex >= DISPLAY_POINTS) {
      displayIndex = 0;
    }
    if (displayCount < DISPLAY_POINTS) {
      displayCount++;
    }
  }
  catch (NumberFormatException e) {
    println("Serial parse error: " + line);
  }
}

// ============================================================
// 画面表示
// ============================================================
void draw() {
  background(255);

  fill(0);
  textSize(20);

  text("Energy Detection / Dynamic Threshold", 20, 30);
  textSize(16);
  text("Energy : Black solid", 20, 60);
  text( "Threshold : Blue solid", 20, 85);
  text("Generated Samples:         " + soundSamples, 200, 60);
  text("Downsampled Samples:   " + downsampledSamples, 200, 85);
  text("Transmitted Samples:   " + transmittedSamples, 450, 85);
  if (droppedSamples > 0) {
    fill(255, 0, 0);
    text("WARNING: Dropped samples = " + droppedSamples, 450, 60);
  }

  // ----------------------------------------------------------
  // グラフ
  // ----------------------------------------------------------
  float top = 140;
  float bottom = 570;
  // 中心線
  stroke(180);
  line(0, bottom, width, bottom);
  if (displayCount == 0) {
    return;
  }
  drawBeatLines();

  // ----------------------------------------------------------
  // Energy Envelope
  // ----------------------------------------------------------
  stroke(0);
  noFill();

  beginShape();
  for (int i = 0; i < displayCount; i++) {
    int index;
    if (displayCount < DISPLAY_POINTS) {
      index = i;
    } else {
      index = (displayIndex + i) % DISPLAY_POINTS;
    }
    float x = map(i, 0, max(1, displayCount - 1), 0, width);
    float y = map(energyWave[index], 0, maxValue, bottom, top);
    vertex(x, y);
  }
  endShape();

  // ----------------------------------------------------------
  // Threshold
  // ----------------------------------------------------------
  stroke(0, 0, 255);
  beginShape();
  for (int i = 0; i < displayCount; i++) {
    int index;
    if (displayCount < DISPLAY_POINTS) {
      index = i;
    } else {
      index = (displayIndex + i) % DISPLAY_POINTS;
    }
    float x = map(i, 0, max(1, displayCount - 1), 0, width);
    float y = map(thresholdWave[index], 0, maxValue, bottom, top);
    vertex(x, y);
  }
  endShape();
}

void drawBeatLines() {
  if (displayCount == 0) {
    return;
  }

  stroke(255, 0, 0);
  for (int i = 0; i < displayCount; i++) {
    int index;
    if (displayCount < DISPLAY_POINTS) {
      index = i;
    } else {
      index = (displayIndex + i) % DISPLAY_POINTS;
    }

    if (!beatWave[index]) {
      continue;
    }

    float x = map(i, 0, max(1, displayCount - 1), 0, width);

    // ビート検出位置に縦線
    line(x, 140, x, 570);
  }
}

// ============================================================
// Low Pass Filter
// ============================================================
class LowPassFilter {
  float alpha;
  float previous = 0;

  LowPassFilter(float cutoff, float sampleRate) {
    float dt = 1.0 / sampleRate;
    float rc = 1.0 / (2.0 * PI * cutoff);
    alpha = dt / (rc + dt);
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
// Down Sampler
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

  BitCrusher(int bitDepth) {
    bits = bitDepth;
  }

  int process(float input) {
    // -1 ～ +1
    input = constrain(input, -1.0, 1.0);

    int levels = (1 << bits) - 1;
    int minValue = -(1 << (bits - 1));
    int maxValue = (1 << (bits - 1)) - 1;

    int value = round((input + 1.0) * levels / 2.0) + minValue;
    return constrain(value, minValue, maxValue);
  }
}

// ============================================================
// 終了処理
// ============================================================
void stop() {
  running = false;
  packingPending = false;

  if (serialThread != null) {
    serialThread.interrupt();
    try {
      serialThread.join(300);
    }
    catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
  }
  if (player != null) {
    player.close();
  }
  if (port != null) {
    port.stop();
  }
  if (minim != null) {
    minim.stop();
  }
  super.stop();
}
