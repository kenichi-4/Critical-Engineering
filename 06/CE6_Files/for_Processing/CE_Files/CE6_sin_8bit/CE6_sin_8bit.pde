import processing.serial.*;

Serial port;

// ===== 通信速度設定 =====
final int BAUD_RATE = 115200;

// ===== 音響信号設定 =====
final float SAMPLE_RATE = 8000.0;   // 8 kHz
final float TONE_FREQ   = 440.0;    // 440 Hz

// 1回にまとめて送るサンプル数
final int BLOCK_SIZE = 64;

// 正弦波生成用
float phase = 0.0;
final float phaseStep = TWO_PI * TONE_FREQ / SAMPLE_RATE;

// ===== 送受信確認用 =====
// 送信値のスケーリングした2乗値を保存しておく
final int MAX_SAMPLES = 100000;
int[] sentData = new int[MAX_SAMPLES];

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
final long SAMPLE_INTERVAL_NS = (long)(1.0e9 / SAMPLE_RATE);


void setup() {
  pixelDensity(2);
  size(900, 400);

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

void draw() {
  background(255);  // 背景色

  // ===== ステータス表示 =====
  fill(0);          // 図形の塗りつぶし色
  textSize(18);     // テキストサイズ

  text("440 Hz sine wave",                     20, 30);
  text("Sample rate : " + SAMPLE_RATE + " Hz", 20, 60);
  text("Baud rate   : " + BAUD_RATE,           20, 90);
  text("Quantize   : 8 bit", 20, 120);
  
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
  if (!running) {     // 波形がMAX_SAMPLESに達して止まったら
    fill(255, 0, 0);
    text("Transmission stopped", 20, 160);
  }
}

void sendBlock() {
  for (int i = 0; i < BLOCK_SIZE; i++) {
    // ===== 正弦波を生成 =====
    float sample = sin(phase);

    // ===== -1.0～+1.0 → -127～+127 =====
    int value = round(sample * 127); // ここを完成させる

    // ===== 送信値の2乗を保存 =====
    if (sendIndex >= MAX_SAMPLES) {
      running = false;
      return;
    }

    sentData[sendIndex] = value * value / 127;
    sendIndex++;

    // ===== 8 bitを送信 =====
    port.write(value & 0xFF); // ここを完成させる

    // ===== 次のサンプル =====
    phase += phaseStep;

    if (phase >= TWO_PI) {
      phase -= TWO_PI;        // 位相を常に2π以下にする
    }
  }
}

void serialEvent(Serial p) {
  while (p.available() > 0) {

    // Processingのread()は0～255を返す
    int receivedByte = p.read();

    // 受信した8 bitを符号付き8 bitとして解釈
    int receivedSample = receivedByte;
    if (receivedSample >= 128) {
      receivedSample -= 256;
    }

    // 送信値と比較
    if (receiveIndex < sendIndex) {
      int sentSample = sentData[receiveIndex];
      int error = receivedSample - sentSample;

      if (error != 0) {
        errorCount++;
        println(
          "ERROR sample=" + receiveIndex +
          " sent=" + sentSample +
          " received=" + receivedSample +
          " error=" + error
          );
      }
      maxError = max(maxError, abs(error));
    }

    // 波形表示用
    float normalized = receivedSample / 127.0; //±127を±1に正規化
    receivedWave[displayIndex] = constrain(normalized, -1.0, 1.0);
    displayIndex++;

    if (displayIndex >= DISPLAY_SAMPLES) {
      displayIndex = 0;
    }
    receiveIndex++;
  }
}

void keyPressed() {
  // Sキー：送信開始／再開
  if (key == 's' || key == 'S') {
    running = true;
    nextSendTime = System.nanoTime();
  }

  // Cキー：カウンタとエラー情報をクリア
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
    phase = 0;
  }
}


void stop() {
  running = false;
  if (port != null) {
    port.stop();
  }
  super.stop();
}
