const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

// Mac TTS 配置
const VOICE = "Tingting"; // 中文女声

const voiceovers = [
  { file: "vo_v2_1.mp3", text: "Nano Typeless，按下即说" },
  { file: "vo_v2_2.mp3", text: "帮我配置 GitHub Actions 自动部署" },
  { file: "vo_v2_3.mp3", text: "纯本地运行，极速响应，支持中英文混合" },
  { file: "vo_v2_4.mp3", text: "别让打字限制你的代码灵感，立即下载" },
];

async function generateTTS() {
  const outputDir = path.join(__dirname, "../public");

  for (const vo of voiceovers) {
    console.log(`Generating: ${vo.file} - "${vo.text}"`);

    const aiffPath = path.join(outputDir, vo.file.replace(".mp3", ".aiff"));
    const mp3Path = path.join(outputDir, vo.file);

    // 使用 Mac say 命令生成 AIFF
    execSync(`say -v ${VOICE} -o "${aiffPath}" "${vo.text}"`);

    // 使用 ffmpeg 转换为 MP3
    execSync(`ffmpeg -y -i "${aiffPath}" -acodec libmp3lame -q:a 2 "${mp3Path}"`);

    // 删除中间的 AIFF 文件
    fs.unlinkSync(aiffPath);

    console.log(`Saved: ${mp3Path}`);
  }

  console.log("All TTS files generated!");
}

generateTTS().catch(console.error);
