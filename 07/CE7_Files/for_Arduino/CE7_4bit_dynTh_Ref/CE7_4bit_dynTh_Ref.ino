// 動的閾値＋リフラクトリ
const int BLOCK_SIZE = 256;     // 256 samples
const int SAMPLE_RATE = 22050;  // 4 bit

// 過去の平均エネルギーの平滑化の係数
const float ENERGY_INTERVAL = (float)BLOCK_SIZE / SAMPLE_RATE;
const float AVERAGE_TAU = 1.0;  // 1.0 s
const float AVERAGE_ALPHA =
  ENERGY_INTERVAL / (AVERAGE_TAU + ENERGY_INTERVAL);

// 動的閾値の倍率（ここはある程度試行錯誤が必要）
const float THRESHOLD_FACTOR = 2.0;  // 1.6/1.8/2.0...など

// リフラクトリ期間
const unsigned long REFRACTORY_TIME = 200;  // ms
unsigned long lastBeatTime = 0;

// 短時間エネルギー
long sumSquare = 0;
int sampleCount = 0;

// 過去の平均エネルギー
float averageEnergy = 0.0;

// 閾値超過状態
bool aboveThreshold = false;

// LEDオン時間
const unsigned long LED_ON_TIME = 20;  // ms
unsigned long ledOnTime = 0;
bool ledIsOn = false;

// ------------------------------------------------------------
// 4 bit signed値（-8～7）を処理
// ------------------------------------------------------------
void processSample(int sample) {
  // 二乗和
  sumSquare += (long)sample * sample;
  sampleCount++;

  // ========================================================
  // BLOCK_SIZEサンプルごとの処理
  // ========================================================
  if (sampleCount >= BLOCK_SIZE) {
    // 短時間エネルギー（ここでは2乗平均値）
    float energy = (float)sumSquare / BLOCK_SIZE;

    // 過去の平均エネルギー
    averageEnergy = averageEnergy + AVERAGE_ALPHA * (energy - averageEnergy);

    // 動的閾値
    float threshold = THRESHOLD_FACTOR * averageEnergy;

    // ------------------------------------------------------
    // 閾値判定
    // ------------------------------------------------------
    int beat = 0;
    unsigned long now = millis();
    bool risingEdge = !aboveThreshold && energy > threshold;
    // 閾値の超過状態は毎回更新
    aboveThreshold = (energy > threshold);

    if (  ) {   // ここを完成させる
      // ビート候補
      beat = 1;
      lastBeatTime = now;

      digitalWrite(LED_BUILTIN, HIGH);
      ledOnTime = now;
      ledIsOn = true;
    }

    // ------------------------------------------------------
    // Processingへ送信
    // energy, threshold（小数点以下第一位まで）, beat
    // ------------------------------------------------------
    Serial.print(energy, 1);
    Serial.print(',');
    Serial.print(threshold, 1);
    Serial.print(',');
    Serial.println(beat);

    // ------------------------------------------------------
    // 次のブロックへ
    // ------------------------------------------------------
    sumSquare = 0;
    sampleCount = 0;
  }
}

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
  // 1 byte = 4 bit sample 2個
  // 上位4 bit -> sample 1
  // 下位4 bit -> sample 2
  // ==========================================================
  while (Serial.available() > 0) {
    updateLED();
    int receivedByte = Serial.read();

    // 上位4 bitを取り出す
    int sample1 = (receivedByte >> 4) & 0x0F;
    // 4 bit signed（2の補数）へ変換
    if (sample1 >= 8) {
      sample1 -= 16;
    }

    // 下位4 bitを取り出す
    int sample2 = receivedByte & 0x0F;
    // 4 bit signed（2の補数）へ変換
    if (sample2 >= 8) {
      sample2 -= 16;
    }

    // 2サンプルを順番に処理
    processSample(sample1);
    processSample(sample2);
  }
}

void updateLED() {
  if (ledIsOn && millis() - ledOnTime >= LED_ON_TIME) {
    digitalWrite(LED_BUILTIN, LOW);
    ledIsOn = false;
  }
}