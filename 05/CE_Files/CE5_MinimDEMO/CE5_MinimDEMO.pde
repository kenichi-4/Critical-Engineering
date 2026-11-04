import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.effects.*;
import javax.sound.sampled.AudioFormat; // フォーマット情報の取得に使用

// ============================================================
// Minim Instances
// ============================================================
Minim minim;
AudioOutput out;
FilePlayer filePlayer;

// ============================================================
// 設定
// ============================================================
final float SAMPLE_RATE = 44100.0; // 入力信号の想定サンプリングレート

// 音声ファイル（ファイルへのパスを記述する）
final String AUDIO_FILE = "/Users/saba/Documents/Processing/CE_Files/Sounds/StratoS.wav";
//final String AUDIO_FILE = "/Users/saba/Documents/Processing/CE_Files/Sounds/techno-trance.wav";
//final String AUDIO_FILE = "/Users/saba/Documents/Processing/CE_Files/Sounds/northside-drive.wav";
//final String AUDIO_FILE = "/Users/saba/Documents/Processing/CE_Files/Sounds/Pattern1.wav";

// Down Sampling（ここを変えてみる）
// 1: 44100, 2: 22050, 3: 14700, 4: 11025, 5: 8820, 6: 7350, 7: 6300
int downFactor = 4;

// Bit Crushing（ここを変えてみる16/12/10/8/6/4/3/2）
int quantizeBit = 8;

// ============================================================
// UGen Instances
// ============================================================
StereoMono stereoMono;
LowPassFS filter;
DownSampler downSampler;
BitCrusher bitCrusher;

// ============================================================
// 動作モード
// ============================================================
final int ORIGINAL = 1;
final int DOWNSAMPLE = 2;
final int BITCRUSH = 3;
final int BOTH = 4;

int processingMode = ORIGINAL;
boolean monoMode = false;
boolean lpfEnabled = true;

// ============================================================
// setup
// ============================================================
void setup() {
  pixelDensity(2); // for Apple Retina Display
  size(700, 400);

  minim = new Minim(this); // Minim のインスタンスを生成

  // 出力は常にSTEREOとする（MONO時には同じ信号をL/Rへ出力する）
  out = minim.getLineOut(Minim.STEREO, 1024, SAMPLE_RATE);

  createAudioChain();  // 各種処理順
  printInstructions(); // Key操作をコンソールに表示
}

// ============================================================
// draw
// ============================================================
void draw() {
  background(30);
  fill(255);
  
  textSize(24);
  text("Audio Quality Comparison", 30, 50);

  textSize(18);
  text("Processing mode : " + modeName(), 30, 110);
  if (monoMode) {
    text("Channel mode    : MONO", 30, 145);
  } else {
    text("Channel mode    : STEREO", 30, 145);
  }

  text("Down factor     : " + downFactor, 30, 180);
  text("Quantization    : " + quantizeBit + " bit", 30, 215);
  if (processingMode == DOWNSAMPLE || processingMode == BOTH) {
    if (lpfEnabled) {
      text("LPF             : ON", 30, 250);
    } else {
      text("LPF             : OFF", 30, 250);
    }
  } else {
    text("LPF             : ---", 30, 250);
  }
  
  textSize(15);
  text("1 : Original", 30, 275);
  text("2 : Down Sampling", 30, 300);
  text("3 : Bit Crushing", 30, 325);
  text("4 : Down Sampling + Bit Crushing", 30, 350);

  text("SPACE : Play/Pause", 360, 275);
  text("M           : Stereo/Mono", 360, 300);
  text("R           : Rewind", 360, 325);
  text("F           : LPF ON/OFF", 360, 350);

}

// ============================================================
// オーディオチェーンの生成
// ============================================================
void createAudioChain() {
  // FilePlayer
  filePlayer = new FilePlayer(minim.loadFileStream(AUDIO_FILE));
  filePlayer.loop();

  // Stereo / Mono変換
  stereoMono = new StereoMono();

  // Down Sampling前のLPF
  float newSampleRate = SAMPLE_RATE / downFactor;
  float cutoff = 0.8 * newSampleRate / 2.0;
  filter = new LowPassFS(cutoff, SAMPLE_RATE);

  // Down Sampler
  downSampler = new DownSampler(downFactor);

  // Bit Crusher
  bitCrusher = new BitCrusher(quantizeBit);

  // 最初は原音
  rebuildPatch();
}

// ============================================================
// 処理モードに応じてpatchを作り直す
// ============================================================
void rebuildPatch() {
  // 既存のpatchをすべて解除
  filePlayer.unpatch(out);
  filePlayer.unpatch(stereoMono);

  stereoMono.unpatch(out);
  stereoMono.unpatch(filter);
  stereoMono.unpatch(downSampler);
  stereoMono.unpatch(bitCrusher);

  filter.unpatch(out);
  filter.unpatch(downSampler);

  downSampler.unpatch(out);
  downSampler.unpatch(bitCrusher);

  bitCrusher.unpatch(out);

  // ----------------------------------------------------------
  // 1. 原音
  // ----------------------------------------------------------
  if (processingMode == ORIGINAL) {
    filePlayer
      .patch(stereoMono)
      .patch(out);
  }

  // ----------------------------------------------------------
  // 2. Down Sampling
  //
  // LPF → DownSampler
  // ----------------------------------------------------------
  else if (processingMode == DOWNSAMPLE) {
    // LPFあり
    if (lpfEnabled) {
      filePlayer
        .patch(stereoMono)
        .patch(filter)
        .patch(downSampler)
        .patch(out);
    }
    // LPFなし
    else {
      filePlayer
        .patch(stereoMono)
        .patch(downSampler)
        .patch(out);
    }
  }

  // ----------------------------------------------------------
  // 3. Bit Crushing
  // ----------------------------------------------------------
  else if (processingMode == BITCRUSH) {
    filePlayer
      .patch(stereoMono)
      .patch(bitCrusher)
      .patch(out);
  }

  // ----------------------------------------------------------
  // 4. Down Sampling + Bit Crushing
  // ----------------------------------------------------------
  else if (processingMode == BOTH) {
    // LPFあり
    if (lpfEnabled) {
      filePlayer
        .patch(stereoMono)
        .patch(filter)
        .patch(downSampler)
        .patch(bitCrusher)
        .patch(out);
    }
    // LPFなし
    else {
      filePlayer
        .patch(stereoMono)
        .patch(downSampler)
        .patch(bitCrusher)
        .patch(out);
    }
  }
}

// ============================================================
// キー入力
// ============================================================
void keyPressed() {
  if (key == '1') {
    processingMode = ORIGINAL;
    rebuildPatch();
    println("Original");
  } else if (key == '2') {
    processingMode = DOWNSAMPLE;
    rebuildPatch();
    println("Down Sampling");
  } else if (key == '3') {
    processingMode = BITCRUSH;
    rebuildPatch();
    println("Bit Crushing");
  } else if (key == '4') {
    processingMode = BOTH;
    rebuildPatch();
    println("Down Sampling + Bit Crushing");
  } else if (key == 'm' || key == 'M') {
    monoMode = !monoMode;
    stereoMono.setMono(monoMode);
    if (monoMode) {
      println("MONO");
    } else {
      println("STEREO");
    }
  } else if (key == ' ') {
    if (filePlayer != null) {
      if (filePlayer.isPlaying()) {
        filePlayer.pause();
        println("Pause");
      } else {
        filePlayer.play();
        println("Play");
      }
    }
  } else if (key == 'r' || key == 'R') {
    if (filePlayer != null) {
      filePlayer.rewind();
      println("Rewind");
    }
  } else if (key == 'f' || key == 'F') {
    if (processingMode == DOWNSAMPLE || processingMode == BOTH) {
      lpfEnabled = !lpfEnabled;
      rebuildPatch();
      if (lpfEnabled) {
        println("LPF ON");
      } else {
        println("LPF OFF");
      }
    }
  }
}

// ============================================================
// 表示用
// ============================================================
String modeName() {
  if (processingMode == ORIGINAL) {
    return "Original";
  }
  if (processingMode == DOWNSAMPLE) {
    return "Down Sampling";
  }
  if (processingMode == BITCRUSH) {
    return "Bit Crushing";
  }
  if (processingMode == BOTH) {
    return "Down Sampling + Bit Crushing";
  }
  return "";
}

void printInstructions() {
  println();
  println("=== Audio Quality Comparison ===");
  println();
  println("1 : Original");
  println("2 : Down Sampling");
  println("3 : Bit Crushing");
  println("4 : Down Sampling + Bit Crushing");
  println();
  println("F     : LPF ON / OFF");
  println("M     : Stereo / Mono");
  println("SPACE : Play / Pause");
  println("R     : Rewind");
  
  println();
}

// ============================================================
// Stereo / Mono UGen
// ============================================================
class StereoMono extends UGen {
  private UGenInput audio;
  private boolean mono = false;

  StereoMono() {
    super();
    audio = new UGenInput(InputType.AUDIO);
  }

  void setMono(boolean value) {
    mono = value;
  }

  @Override
    protected void uGenerate(float[] channels) {

    float[] input = audio.getLastValues();
    float left = input[0];
    float right;

    if (input.length > 1) {
      right = input[1];
    } else {
      right = left;
    }

    // MONO
    if (mono) {
      float value = 0.5 * (left + right);
      channels[0] = value;

      if (channels.length > 1) {
        channels[1] = value;
      }
    }

    // STEREO
    else {
      channels[0] = left;

      if (channels.length > 1) {
        channels[1] = right;
      }
    }
  }
}

// ============================================================
// Down Sampler
// ============================================================
class DownSampler extends UGen {
  private int factor;
  private int counter;

  private float lastLeft;
  private float lastRight;

  private UGenInput audio;

  DownSampler(int downsampleFactor) {
    super();
    factor = downsampleFactor;

    counter = 0;
    lastLeft = 0;
    lastRight = 0;

    audio = new UGenInput(InputType.AUDIO);
  }


  @Override
    protected void uGenerate(float[] channels) {

    float[] input = audio.getLastValues();
    float left = input[0];
    float right;

    if (input.length > 1) {
      right = input[1];
    } else {
      right = left;
    }

    counter++;

    // factorサンプルごとに新しい値を取得
    if (counter >= factor) {
      lastLeft = left;
      lastRight = right;
      counter = 0;
    }
    
    // Factorサンプルごとに値を更新し、その間は前の値を保持する
    // 出力サンプリングレートは44.1 kHzのまま
    // 次のサンプル取得まで値を保持
    channels[0] = lastLeft;

    if (channels.length > 1) {
      channels[1] = lastRight;
    }
  }
}


// ============================================================
// Bit Crusher
// ============================================================
class BitCrusher extends UGen {
  private int bits;
  private float step;
  private UGenInput audio;

  BitCrusher(int bitDepth) {
    super();
    bits = bitDepth;
    step = 2.0 / pow(2, bits);
    audio = new UGenInput(InputType.AUDIO);
  }

  @Override
    protected void uGenerate(float[] channels) {

    float[] input = audio.getLastValues();
    // LEFT
    float left = constrain(input[0], -1, 1);

    left = round(left / step) * step;
    left = constrain(left, -1, 1);
    channels[0] = left;

    // RIGHT
    if (channels.length > 1) {
      float right;

      if (input.length > 1) {
        right = input[1];
      } else {
        right = input[0];
      }

      right = constrain(right, -1, 1);

      right = round(right / step) * step;
      right = constrain(right, -1, 1);
      channels[1] = right;
    }
  }
}

// ============================================================
// 終了処理
// ============================================================
void stop() {
  if (filePlayer != null) {
    filePlayer.close();
  }
  if (out != null) {
    out.close();
  }
  if (minim != null) {
    minim.stop();
  }
  super.stop();
}
