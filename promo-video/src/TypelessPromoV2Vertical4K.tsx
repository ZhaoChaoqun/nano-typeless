import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  Sequence,
  Img,
  staticFile,
  Audio,
} from "remotion";

// 颜色配置
const colors = {
  background: "#0d1117",
  text: "#ffffff",
  textMuted: "rgba(255, 255, 255, 0.6)",
  accent: "#8b5cf6",
  green: "#10b981",
  claudeOrange: "#d97706",
};

// 打字机效果的光标 (4K 版本 - 尺寸 x2)
const Cursor: React.FC<{ visible?: boolean }> = ({ visible = true }) => {
  const frame = useCurrentFrame();
  const blink = Math.floor(frame / 8) % 2 === 0;

  return (
    <span
      style={{
        display: "inline-block",
        width: 8,
        height: 72,
        background: colors.claudeOrange,
        marginLeft: 4,
        verticalAlign: "middle",
        opacity: visible && blink ? 1 : 0,
      }}
    />
  );
};

// 竖版场景1：转场 - 黑屏 + 图标闪现 (4K)
const Scene1_TransitionVertical: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const blackScreenEnd = 15;
  const isBlackScreen = frame < blackScreenEnd;

  const iconScale = spring({
    frame: frame - blackScreenEnd,
    fps,
    config: { damping: 10, stiffness: 100 },
  });

  const iconOpacity = interpolate(
    frame,
    [blackScreenEnd, blackScreenEnd + 10],
    [0, 1],
    { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
  );

  const glowIntensity = 0.3 + Math.sin(frame * 0.2) * 0.2;

  const textOpacity = interpolate(frame, [40, 55], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {!isBlackScreen && (
        <>
          {/* 紫色光晕背景 - 铺满 */}
          <div
            style={{
              position: "absolute",
              top: "40%",
              left: "50%",
              width: "150%",
              height: "80%",
              marginTop: "-40%",
              marginLeft: "-75%",
              background: `radial-gradient(circle, rgba(139, 92, 246, ${glowIntensity}) 0%, transparent 70%)`,
              filter: "blur(160px)",
            }}
          />

          {/* App 图标 - 更大 */}
          <div
            style={{
              position: "absolute",
              top: "38%",
              left: "50%",
              transform: `translate(-50%, -50%) scale(${Math.max(0, iconScale)})`,
              opacity: iconOpacity,
            }}
          >
            <Img
              src={staticFile("icon_512x512.png")}
              style={{
                width: 400,
                height: 400,
                borderRadius: 96,
                boxShadow: "0 0 200px rgba(139, 92, 246, 0.6)",
              }}
            />
          </div>

          {/* 标题和副标题 - 居中偏下 */}
          <div
            style={{
              position: "absolute",
              top: "58%",
              left: "50%",
              transform: "translateX(-50%)",
              opacity: textOpacity,
              textAlign: "center",
              width: "90%",
            }}
          >
            <h2
              style={{
                fontSize: 144,
                fontWeight: 700,
                color: colors.text,
                margin: 0,
                fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
              }}
            >
              Nano Typeless
            </h2>
            <p
              style={{
                fontSize: 84,
                color: colors.textMuted,
                marginTop: 40,
                fontWeight: 500,
                letterSpacing: "16px",
              }}
            >
              PRESS. SPEAK.
            </p>
          </div>
        </>
      )}
    </AbsoluteFill>
  );
};

// 竖版场景2：核心演示 - Claude Code + 顶部 HUD（不遮挡界面）(4K)
const Scene2_DemoVertical: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const voiceText = "帮我配置 GitHub Actions 自动部署";

  // 时间轴
  const claudeAppearFrame = 0;
  const fnKeyPressFrame = 20;
  const listeningEndFrame = 105;
  const hudFadeOutEndFrame = 112;
  const textAppearFrame = 119;
  const textTypingSpeed = 8;

  // 文字打字效果
  const typedLength = frame > textAppearFrame
    ? Math.floor((frame - textAppearFrame) * textTypingSpeed)
    : 0;
  const displayText = voiceText.slice(0, Math.min(typedLength, voiceText.length));
  const isTypingComplete = typedLength >= voiceText.length;

  const isRecording = frame > fnKeyPressFrame && frame < listeningEndFrame;

  // Claude Code 界面淡入（始终 100% 可见，无暗化）
  const claudeOpacity = interpolate(
    frame,
    [claudeAppearFrame, claudeAppearFrame + 15],
    [0, 1],
    { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
  );

  // HUD 从顶部滑入动画
  const hudSlideIn = spring({
    frame: frame - fnKeyPressFrame,
    fps,
    config: { damping: 15, stiffness: 120 },
  });

  // HUD 滑出动画
  const hudSlideOut = frame > listeningEndFrame
    ? interpolate(frame, [listeningEndFrame, hudFadeOutEndFrame], [0, -240], {
        extrapolateRight: "clamp",
      })
    : 0;

  const hudY = interpolate(hudSlideIn, [0, 1], [-240, 160]) + hudSlideOut;

  const hudOpacity = interpolate(
    frame,
    [fnKeyPressFrame, fnKeyPressFrame + 8, listeningEndFrame - 3, hudFadeOutEndFrame],
    [0, 1, 1, 0],
    { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
  );

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {/* Claude Code 界面（始终完全可见） */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          opacity: claudeOpacity,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          padding: 80,
          paddingTop: 360,
        }}
      >
        {/* Claude Code 卡片 */}
        <div
          style={{
            width: "100%",
            maxWidth: 2000,
            background: "#0d1117",
            borderRadius: 48,
            overflow: "hidden",
            boxShadow: "0 40px 120px rgba(0,0,0,0.5)",
            border: "2px solid rgba(255,255,255,0.1)",
          }}
        >
          <div
            style={{
              padding: 80,
              fontFamily: "SF Mono, Menlo, monospace",
              color: colors.text,
            }}
          >
            {/* 顶部标题栏 */}
            <div
              style={{
                borderBottom: "2px solid rgba(255,255,255,0.2)",
                paddingBottom: 48,
                marginBottom: 64,
                textAlign: "center",
                fontSize: 40,
                color: "rgba(255,255,255,0.5)",
              }}
            >
              ─── Claude Code ───
            </div>

            {/* Claude Logo */}
            <div
              style={{
                textAlign: "center",
                marginBottom: 80,
              }}
            >
              <div style={{ fontSize: 72, lineHeight: 1.2, color: "#d97706" }}>
                <p style={{ margin: 0 }}>▐▛███▜▌</p>
                <p style={{ margin: 0 }}>▝▜█████▛▘</p>
              </div>
              <p style={{ fontSize: 36, color: "rgba(255,255,255,0.5)", marginTop: 32 }}>
                claude-opus-4.5
              </p>
            </div>

            {/* 语音输入区域 */}
            <div
              style={{
                padding: 64,
                background: "rgba(139, 92, 246, 0.1)",
                borderRadius: 32,
                border: "2px solid rgba(139, 92, 246, 0.3)",
                height: 200,
                display: "flex",
                alignItems: "center",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 32 }}>
                <span style={{ color: "#8b5cf6", fontSize: 56, lineHeight: 1 }}>❯</span>
                <p
                  style={{
                    fontSize: 64,
                    color: colors.text,
                    margin: 0,
                    lineHeight: 1.6,
                    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
                  }}
                >
                  {frame > textAppearFrame ? (
                    <>
                      {displayText}
                      {!isTypingComplete && <Cursor />}
                    </>
                  ) : (
                    <Cursor />
                  )}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* 顶部 HUD：Typeless 录音指示器（紧凑横条，不遮挡主界面） */}
      {frame > fnKeyPressFrame && frame < hudFadeOutEndFrame + 5 && (
        <div
          style={{
            position: "absolute",
            top: hudY,
            left: "50%",
            transform: "translateX(-50%)",
            opacity: hudOpacity,
            background: "rgba(25, 25, 30, 0.92)",
            backdropFilter: "blur(40px)",
            borderRadius: 100,
            padding: "40px 72px",
            boxShadow: "0 16px 64px rgba(0,0,0,0.4), 0 0 0 2px rgba(255,255,255,0.08)",
            display: "flex",
            alignItems: "center",
            gap: 48,
          }}
        >
          {/* 波形动画（紧凑版） */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 12,
              height: 80,
            }}
          >
            {Array.from({ length: 7 }).map((_, i) => {
              const centerIndex = 3;
              const distanceFromCenter = Math.abs(i - centerIndex);
              const baseHeight = Math.max(32, 72 - distanceFromCenter * 12);
              const amplitude = Math.max(12, 32 - distanceFromCenter * 6);
              const frequency = 0.4 + (i % 3) * 0.1;
              const phase = i * 0.7;
              const barHeight = isRecording
                ? baseHeight + Math.sin((frame * frequency) + phase) * amplitude
                : 24;

              return (
                <div
                  key={i}
                  style={{
                    width: 12,
                    height: Math.max(24, barHeight),
                    background: isRecording
                      ? "linear-gradient(180deg, rgba(255,255,255,0.95), rgba(255,255,255,0.5))"
                      : "rgba(255,255,255,0.3)",
                    borderRadius: 6,
                  }}
                />
              );
            })}
          </div>

          {/* 正在聆听文字 */}
          <p
            style={{
              fontSize: 44,
              color: "rgba(255,255,255,0.85)",
              margin: 0,
              fontWeight: 500,
              fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
              whiteSpace: "nowrap",
            }}
          >
            正在聆听...
          </p>
        </div>
      )}

      {/* 底部字幕 */}
      {frame > 90 && (
        <div
          style={{
            position: "absolute",
            bottom: 200,
            left: "50%",
            transform: "translateX(-50%)",
            background: "rgba(0, 0, 0, 0.85)",
            padding: "40px 80px",
            borderRadius: 32,
            opacity: interpolate(frame, [90, 105], [0, 1], {
              extrapolateRight: "clamp",
            }),
          }}
        >
          <p style={{ fontSize: 64, color: colors.text, margin: 0 }}>
            🎤 语音秒变代码
          </p>
        </div>
      )}
    </AbsoluteFill>
  );
};

// 竖版场景3：三个卖点 - 全屏闪切（放慢切换速度）(4K)
const Scene3_FeaturesVertical: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // 每个卖点 60 帧（2秒）
  const featureIndex = Math.floor(frame / 60);

  const features = [
    {
      icon: "lock.png",
      title: "100% Local",
      subtitle: "纯本地运行",
      desc: "数据永不上传",
      color: "#10b981",
    },
    {
      icon: "high-voltage.png",
      title: "Instant",
      subtitle: "极速响应",
      desc: "毫秒级识别",
      color: "#f59e0b",
    },
    {
      icon: "globe-with-meridians.png",
      title: "Mixed",
      subtitle: "中英文混合",
      desc: "智能语言切换",
      color: "#8b5cf6",
    },
  ];

  const currentFeature = features[Math.min(featureIndex, features.length - 1)];
  const featureFrame = frame % 60;

  const scale = spring({
    frame: featureFrame,
    fps,
    config: { damping: 12 },
  });

  // 调整淡入淡出时间适配 60 帧
  const opacity = interpolate(featureFrame, [0, 12, 48, 60], [0, 1, 1, 0], {
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {/* 背景光晕 - 铺满 */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `radial-gradient(circle at 50% 40%, ${currentFeature.color}30 0%, transparent 70%)`,
        }}
      />

      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: `translate(-50%, -50%) scale(${Math.max(0, scale)})`,
          opacity,
          textAlign: "center",
          width: "90%",
        }}
      >
        {/* 图标 - 更大 */}
        <Img
          src={staticFile(currentFeature.icon)}
          style={{
            width: 360,
            height: 360,
            marginBottom: 96,
          }}
        />

        {/* 主标题 */}
        <h1
          style={{
            fontSize: 192,
            fontWeight: 700,
            color: currentFeature.color,
            margin: 0,
            fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
            textShadow: `0 0 120px ${currentFeature.color}80`,
          }}
        >
          {currentFeature.title}
        </h1>

        {/* 副标题 */}
        <p
          style={{
            fontSize: 96,
            color: colors.text,
            marginTop: 48,
            fontWeight: 500,
          }}
        >
          {currentFeature.subtitle}
        </p>

        {/* 描述 */}
        <p
          style={{
            fontSize: 64,
            color: colors.textMuted,
            marginTop: 32,
          }}
        >
          {currentFeature.desc}
        </p>
      </div>

      {/* 进度指示器 */}
      <div
        style={{
          position: "absolute",
          bottom: 240,
          left: "50%",
          transform: "translateX(-50%)",
          display: "flex",
          gap: 32,
        }}
      >
        {features.map((_, i) => (
          <div
            key={i}
            style={{
              width: 120,
              height: 16,
              borderRadius: 8,
              background:
                i === featureIndex
                  ? currentFeature.color
                  : "rgba(255,255,255,0.2)",
            }}
          />
        ))}
      </div>
    </AbsoluteFill>
  );
};

// 竖版场景4：CTA - 全屏 (4K)
const Scene4_CTAVertical: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const titleScale = spring({
    frame,
    fps,
    config: { damping: 12 },
  });

  const titleOpacity = interpolate(frame, [0, 20], [0, 1], {
    extrapolateRight: "clamp",
  });

  const commandOpacity = interpolate(frame, [30, 50], [0, 1], {
    extrapolateRight: "clamp",
  });

  const sloganOpacity = interpolate(frame, [60, 80], [0, 1], {
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {/* 紫色光晕背景 */}
      <div
        style={{
          position: "absolute",
          top: "30%",
          left: "50%",
          width: "200%",
          height: "100%",
          marginLeft: "-100%",
          marginTop: "-50%",
          background: "radial-gradient(circle, rgba(139, 92, 246, 0.25) 0%, transparent 60%)",
          filter: "blur(200px)",
        }}
      />

      {/* 主要内容 */}
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: "translate(-50%, -50%)",
          textAlign: "center",
          width: "90%",
        }}
      >
        {/* Logo + 标题 */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 48,
            opacity: titleOpacity,
            transform: `scale(${Math.max(0, titleScale)})`,
            marginBottom: 120,
          }}
        >
          <Img
            src={staticFile("icon_512x512.png")}
            style={{
              width: 240,
              height: 240,
              borderRadius: 56,
              boxShadow: "0 0 120px rgba(139, 92, 246, 0.4)",
            }}
          />
          <h1
            style={{
              fontSize: 128,
              fontWeight: 700,
              color: colors.text,
              margin: 0,
              fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
            }}
          >
            Nano Typeless
          </h1>
        </div>

        {/* Slogan */}
        <p
          style={{
            fontSize: 72,
            color: colors.textMuted,
            marginBottom: 120,
            opacity: sloganOpacity,
          }}
        >
          别让打字限制你的代码灵感
        </p>

        {/* 安装命令 */}
        <div
          style={{
            opacity: commandOpacity,
            background: "rgba(255, 255, 255, 0.05)",
            borderRadius: 40,
            padding: "64px 80px",
            border: "2px solid rgba(255, 255, 255, 0.1)",
            marginBottom: 80,
          }}
        >
          <p
            style={{
              fontSize: 40,
              color: colors.textMuted,
              margin: 0,
              marginBottom: 32,
            }}
          >
            立即安装
          </p>
          <code
            style={{
              fontSize: 48,
              color: colors.green,
              fontFamily: "SF Mono, Menlo, monospace",
              display: "block",
              marginBottom: 24,
            }}
          >
            brew tap ZhaoChaoqun/typeless
          </code>
          <code
            style={{
              fontSize: 48,
              color: colors.green,
              fontFamily: "SF Mono, Menlo, monospace",
            }}
          >
            brew install --cask nano-typeless
          </code>
        </div>

        {/* GitHub */}
        <div
          style={{
            opacity: commandOpacity,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 24,
          }}
        >
          <span style={{ fontSize: 56 }}>⭐</span>
          <span
            style={{
              fontSize: 44,
              color: colors.textMuted,
            }}
          >
            github.com/ZhaoChaoqun/typeless
          </span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

// 竖版 4K 主视频组件
export const TypelessPromoV2Vertical4K: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {/* 背景音乐 */}
      <Audio src={staticFile("mehul-choudhary-effortless.mp3")} volume={0.25} />

      {/* 旁白：场景1 - Nano Typeless，按下即说 */}
      <Sequence from={20}>
        <Audio src={staticFile("vo_v2_1.mp3")} volume={1} />
      </Sequence>

      {/* 旁白：场景2 - 帮我重构这个 React Hook */}
      <Sequence from={120}>
        <Audio src={staticFile("vo_v2_2.mp3")} volume={1} />
      </Sequence>

      {/* 旁白：场景3 - 纯本地运行，极速响应，支持中英文混合 */}
      <Sequence from={260}>
        <Audio src={staticFile("vo_v2_3.mp3")} volume={1} />
      </Sequence>

      {/* 旁白：场景4 - 别让打字限制你的代码灵感，立即下载 */}
      <Sequence from={440}>
        <Audio src={staticFile("vo_v2_4.mp3")} volume={1} />
      </Sequence>

      {/* 场景1：转场 0-90帧 (0-3秒) */}
      <Sequence from={0} durationInFrames={90}>
        <Scene1_TransitionVertical />
      </Sequence>

      {/* 场景2：核心演示 90-240帧 (3-8秒) */}
      <Sequence from={90} durationInFrames={150}>
        <Scene2_DemoVertical />
      </Sequence>

      {/* 场景3：硬核背书 240-420帧 (8-14秒) - 3个卖点各2秒 */}
      <Sequence from={240} durationInFrames={180}>
        <Scene3_FeaturesVertical />
      </Sequence>

      {/* 场景4：CTA 420-555帧 (14-18.5秒) */}
      <Sequence from={420} durationInFrames={135}>
        <Scene4_CTAVertical />
      </Sequence>
    </AbsoluteFill>
  );
};
