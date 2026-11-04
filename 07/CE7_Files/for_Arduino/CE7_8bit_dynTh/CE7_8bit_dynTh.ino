// 動的閾値
const int BLOCK_SIZE = 128;
const int SAMPLE_RATE = 11025;  // 8 bit

// 過去の平均エネルギーの平滑化の係数
const float ENERGY_INTERVAL = (float)BLOCK_SIZE / SAMPLE_RATE;
const float AVERAGE_TAU = 1.0;  // 1.0  s
const float AVERAGE_ALPHA = ENERGY_INTERVAL / (AVERAGE_TAU + ENERGY_INTERVAL);

// 動的閾値の倍率（ここはある程度試行錯誤が必要）
const float THRESHOLD_FACTOR = 2.0;  // 1.6/1.8/2.0...など

// 短時間エネルギー
long sumSquare = 0;
int sampleCount = 0;

// 過去の平均エネルギー
float averageEnergy = 0.0;

// 閾値超過状態
bool aboveThreshold = false;

// LED点灯時間
const unsigned long LED_ON_TIME = 20;  // ms
unsigned long ledOnTime = 0;
bool ledIsOn = false;

void setup() {
  Serial.begin(115200);
//  Serial.begin(230400);

  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);
}

void loop() {
  // LED消灯
  updateLED();

  // ==========================================================
  // 音響データ受信
  // ==========================================================
  while (Serial.available() > 0) {
    updateLED();

    // 1 byte受信
    int receivedByte = Serial.read();

    // signed 8 bitとして解釈
    int8_t sample = (int8_t)receivedByte;
    int value = (int)sample;

    // 二乗和
    sumSquare += (long)value * value;
    sampleCount++;

    // ========================================================
    // BLOCK_SIZEサンプルごとの処理
    // ========================================================
    if (sampleCount >= BLOCK_SIZE) {
      // 短時間エネルギー(2乗の平均）
      float energy = (float)sumSquare / BLOCK_SIZE;

      // 過去の平均エネルギー
      averageEnergy = ;  // ここを完成させる

      // 動的閾値
      float threshold = THRESHOLD_FACTOR * averageEnergy;

      // ------------------------------------------------------
      // 閾値判定
      // ------------------------------------------------------
      int beat = 0;

      if (  ) { // ここを完成させる
        // ビート候補
        beat = 1;
        aboveThreshold = true;

        digitalWrite(LED_BUILTIN, HIGH);
        ledOnTime = millis();
        ledIsOn = true;
      }

      // ------------------------------------------------------
      // 閾値より下に戻った
      // ------------------------------------------------------
      if (aboveThreshold && energy <= threshold) {
        aboveThreshold = false;
      }

      // ------------------------------------------------------
      // Processingへ送信
      // energy と threshold （小数点以下第一位まで）とbeat判定結果を送る
      // ------------------------------------------------------
        Serial.print(energy, 1);
        Serial.print(',');
        Serial.print(threshold, 1);
        Serial.print(',');
        Serial.println(beat);

      // 次のブロックへ
      sumSquare = 0;
      sampleCount = 0;
    }
  }
}

void updateLED() {
  if (ledIsOn && millis() - ledOnTime >= LED_ON_TIME) {
    digitalWrite(LED_BUILTIN, LOW);
    ledIsOn = false;
  }
}