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

// 颜色配置 - iPhone 发布会风格
const colors = {
  background: "#000000",
  text: "#ffffff",
  textMuted: "rgba(255, 255, 255, 0.6)",
  accent: "#0071e3", // Apple Blue
  gradientStart: "#1a1a1a",
  gradientEnd: "#000000",
};

// 逼真烟雾效果 - 模拟 iPhone 发布会风格的紫色烟雾
const SmokeEffect: React.FC<{ intensity?: number }> = ({ intensity = 1 }) => {
  const frame = useCurrentFrame();

  // 烟雾层配置 - 多层叠加产生深度感
  const smokeLayers = [
    // 底层大块烟雾
    { id: 0, x: -200, y: 300, width: 900, height: 700, rotation: 0, speed: 0.3, scaleBase: 1.2, color: "rgba(90, 50, 150, 0.4)" },
    { id: 1, x: 1200, y: 400, width: 850, height: 650, rotation: 10, speed: 0.25, scaleBase: 1.1, color: "rgba(120, 80, 180, 0.35)" },
    // 中层流动烟雾
    { id: 2, x: 400, y: 100, width: 700, height: 500, rotation: -15, speed: 0.4, scaleBase: 1.0, color: "rgba(140, 100, 200, 0.3)" },
    { id: 3, x: 800, y: 600, width: 750, height: 550, rotation: 5, speed: 0.35, scaleBase: 1.05, color: "rgba(100, 60, 160, 0.35)" },
    // 上层细节烟雾
    { id: 4, x: 200, y: 500, width: 500, height: 400, rotation: -5, speed: 0.5, scaleBase: 0.9, color: "rgba(160, 120, 220, 0.25)" },
    { id: 5, x: 1100, y: 150, width: 550, height: 450, rotation: 12, speed: 0.45, scaleBase: 0.95, color: "rgba(130, 90, 190, 0.28)" },
  ];

  // 漂浮的烟雾团
  const smokeBlobs = [
    { id: 0, baseX: 300, baseY: 250, size: 200, phaseX: 0, phaseY: 0.5, speedX: 0.015, speedY: 0.012, color: "rgba(150, 100, 210, 0.5)" },
    { id: 1, baseX: 1500, baseY: 400, size: 250, phaseX: 1, phaseY: 1.5, speedX: 0.012, speedY: 0.018, color: "rgba(120, 80, 180, 0.45)" },
    { id: 2, baseX: 900, baseY: 700, size: 180, phaseX: 2, phaseY: 0, speedX: 0.018, speedY: 0.01, color: "rgba(170, 130, 230, 0.4)" },
    { id: 3, baseX: 600, baseY: 150, size: 220, phaseX: 0.5, phaseY: 2, speedX: 0.01, speedY: 0.015, color: "rgba(100, 70, 160, 0.5)" },
    { id: 4, baseX: 1300, baseY: 800, size: 190, phaseX: 1.5, phaseY: 1, speedX: 0.014, speedY: 0.016, color: "rgba(140, 100, 200, 0.42)" },
  ];

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        overflow: "hidden",
        opacity: intensity,
        background: "linear-gradient(180deg, #0a0512 0%, #000000 50%, #0a0512 100%)",
      }}
    >
      {/* 底层深色渐变 */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `
            radial-gradient(ellipse 120% 80% at 20% 30%, rgba(80, 40, 140, 0.3) 0%, transparent 60%),
            radial-gradient(ellipse 100% 70% at 80% 70%, rgba(100, 60, 160, 0.25) 0%, transparent 55%)
          `,
        }}
      />

      {/* 大块烟雾层 - 使用 CSS 渐变模拟体积感 */}
      {smokeLayers.map((layer) => {
        const time = frame * layer.speed;
        const offsetX = Math.sin(time * 0.02 + layer.id) * 50;
        const offsetY = Math.cos(time * 0.015 + layer.id * 0.5) * 30;
        const scale = layer.scaleBase + Math.sin(time * 0.01 + layer.id) * 0.1;
        const rotation = layer.rotation + Math.sin(time * 0.008 + layer.id) * 5;
        const opacity = 0.7 + Math.sin(time * 0.012 + layer.id * 0.7) * 0.3;

        return (
          <div
            key={`layer-${layer.id}`}
            style={{
              position: "absolute",
              left: layer.x + offsetX,
              top: layer.y + offsetY,
              width: layer.width,
              height: layer.height,
              borderRadius: "50%",
              background: `radial-gradient(ellipse at center, ${layer.color} 0%, transparent 70%)`,
              transform: `scale(${scale}) rotate(${rotation}deg)`,
              filter: "blur(60px)",
              opacity,
              mixBlendMode: "screen",
            }}
          />
        );
      })}

      {/* 漂浮烟雾团 - 更高对比度的亮点 */}
      {smokeBlobs.map((blob) => {
        const x = blob.baseX + Math.sin(frame * blob.speedX + blob.phaseX) * 100;
        const y = blob.baseY + Math.cos(frame * blob.speedY + blob.phaseY) * 80;
        const scale = 1 + Math.sin(frame * 0.02 + blob.id) * 0.15;
        const opacity = 0.6 + Math.sin(frame * 0.015 + blob.id * 0.5) * 0.4;

        return (
          <div
            key={`blob-${blob.id}`}
            style={{
              position: "absolute",
              left: x,
              top: y,
              width: blob.size,
              height: blob.size,
              borderRadius: "50%",
              background: `radial-gradient(circle at 40% 40%, ${blob.color}, transparent 70%)`,
              transform: `scale(${scale})`,
              filter: "blur(40px)",
              opacity,
              mixBlendMode: "screen",
            }}
          />
        );
      })}

      {/* 中心高光 - 模拟光源照射烟雾 */}
      <div
        style={{
          position: "absolute",
          left: "50%",
          top: "45%",
          width: 800,
          height: 600,
          marginLeft: -400,
          marginTop: -300,
          background: `
            radial-gradient(ellipse 100% 80% at 50% 50%,
              rgba(180, 150, 255, 0.15) 0%,
              rgba(140, 100, 220, 0.08) 30%,
              transparent 60%)
          `,
          filter: "blur(30px)",
          opacity: 0.5 + Math.sin(frame * 0.015) * 0.2,
        }}
      />

      {/* 边缘暗角 */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `radial-gradient(ellipse 80% 80% at 50% 50%, transparent 30%, rgba(0,0,0,0.6) 100%)`,
          pointerEvents: "none",
        }}
      />

      {/* 顶部和底部渐隐 */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `
            linear-gradient(to bottom, rgba(0,0,0,0.8) 0%, transparent 15%, transparent 85%, rgba(0,0,0,0.8) 100%)
          `,
          pointerEvents: "none",
        }}
      />
    </div>
  );
};

// 浮动 Emoji 背景（保留但可选）
const FloatingEmojis: React.FC<{ opacity?: number }> = ({ opacity = 0.15 }) => {
  const frame = useCurrentFrame();
  const emojis = ["🎤", "💬", "⚡", "🔒", "🌐", "✨", "🎯", "💡", "🚀", "⌨️"];

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        overflow: "hidden",
        opacity,
      }}
    >
      {emojis.map((emoji, i) => {
        const x = (i * 192 + frame * (0.3 + i * 0.1)) % 2100 - 100;
        const y = (i * 108 + Math.sin(frame * 0.02 + i) * 50) % 1200;
        const scale = 0.8 + Math.sin(frame * 0.03 + i * 2) * 0.2;
        const rotation = Math.sin(frame * 0.01 + i) * 15;

        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: x,
              top: y,
              fontSize: 60 + i * 5,
              transform: `scale(${scale}) rotate(${rotation}deg)`,
              filter: "blur(1px)",
            }}
          >
            {emoji}
          </div>
        );
      })}
    </div>
  );
};

// HUD 组件 - 模拟实际的 OverlayView
const HUD: React.FC<{ state: "recording" | "processing"; frame: number }> = ({
  state,
  frame,
}) => {
  const dots = 5;

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 4,
        padding: "12px 20px",
        background: "rgba(0, 0, 0, 0.85)",
        borderRadius: 22,
        boxShadow: "0 4px 20px rgba(0, 0, 0, 0.5)",
      }}
    >
      {state === "recording" ? (
        // 录音动画 - 5个跳动的白点
        [...Array(dots)].map((_, i) => {
          const phase = frame * 0.3 + i * 0.5;
          const offset = Math.sin(phase) * 6;
          return (
            <div
              key={i}
              style={{
                width: 8,
                height: 8,
                borderRadius: "50%",
                background: "#ffffff",
                transform: `translateY(${offset}px)`,
              }}
            />
          );
        })
      ) : (
        // 处理中指示器
        <div
          style={{
            width: 20,
            height: 20,
            border: "2px solid rgba(255,255,255,0.3)",
            borderTopColor: "#fff",
            borderRadius: "50%",
            transform: `rotate(${frame * 10}deg)`,
          }}
        />
      )}
    </div>
  );
};

// 模拟编辑器/输入区域
const InputArea: React.FC<{
  text: string;
  showCursor?: boolean;
}> = ({ text, showCursor = true }) => {
  const frame = useCurrentFrame();
  const cursorVisible = showCursor && Math.floor(frame / 15) % 2 === 0;

  return (
    <div
      style={{
        background: "rgba(255, 255, 255, 0.05)",
        borderRadius: 16,
        padding: "32px 40px",
        minWidth: 600,
        minHeight: 100,
        border: "1px solid rgba(255, 255, 255, 0.1)",
        backdropFilter: "blur(20px)",
      }}
    >
      <p
        style={{
          fontSize: 32,
          fontWeight: 400,
          color: colors.text,
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif",
          lineHeight: 1.5,
          margin: 0,
        }}
      >
        {text}
        {cursorVisible && (
          <span
            style={{
              display: "inline-block",
              width: 3,
              height: 36,
              background: colors.accent,
              marginLeft: 2,
              verticalAlign: "middle",
            }}
          />
        )}
      </p>
    </div>
  );
};

// 场景1：开场 - Logo + nano typeless + Press. Speak.
const Scene1_Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const logoScale = spring({
    frame,
    fps,
    config: { damping: 12 },
  });

  const logoOpacity = interpolate(frame, [0, 20], [0, 1], {
    extrapolateRight: "clamp",
  });

  const titleOpacity = interpolate(frame, [25, 45], [0, 1], {
    extrapolateRight: "clamp",
  });

  const titleY = interpolate(frame, [25, 45], [30, 0], {
    extrapolateRight: "clamp",
  });

  const subtitleOpacity = interpolate(frame, [50, 70], [0, 1], {
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: colors.background,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <SmokeEffect intensity={0.9} />

      {/* App Icon */}
      <Img
        src={staticFile("icon_512x512.png")}
        style={{
          transform: `scale(${logoScale})`,
          opacity: logoOpacity,
          marginBottom: 32,
          width: 120,
          height: 120,
          borderRadius: 28,
          boxShadow: "0 20px 60px rgba(102, 126, 234, 0.4)",
        }}
      />

      {/* Title */}
      <h1
        style={{
          fontSize: 96,
          fontWeight: 700,
          color: colors.text,
          opacity: titleOpacity,
          transform: `translateY(${titleY}px)`,
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif",
          letterSpacing: "-2px",
          margin: 0,
        }}
      >
        nano typeless
      </h1>

      {/* Subtitle */}
      <p
        style={{
          fontSize: 36,
          fontWeight: 500,
          color: colors.textMuted,
          opacity: subtitleOpacity,
          marginTop: 20,
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif",
          letterSpacing: "8px",
        }}
      >
        PRESS. SPEAK.
      </p>
    </AbsoluteFill>
  );
};

// 场景2：展示 HUD 录音
const Scene2_Recording: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const hudOpacity = interpolate(frame, [0, 15], [0, 1], {
    extrapolateRight: "clamp",
  });

  const hudScale = spring({
    frame,
    fps,
    config: { damping: 15 },
  });

  const fnKeyOpacity = interpolate(frame, [20, 35], [0, 1], {
    extrapolateRight: "clamp",
  });

  const fnKeyPressed = frame > 40;

  return (
    <AbsoluteFill
      style={{
        background: colors.background,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <SmokeEffect intensity={0.8} />

      {/* HUD */}
      <div
        style={{
          position: "absolute",
          top: 200,
          opacity: hudOpacity,
          transform: `scale(${hudScale})`,
        }}
      >
        <HUD state="recording" frame={frame} />
      </div>

      {/* Fn 键提示 */}
      <div
        style={{
          position: "absolute",
          bottom: 250,
          display: "flex",
          alignItems: "center",
          gap: 20,
          opacity: fnKeyOpacity,
        }}
      >
        <div
          style={{
            width: 80,
            height: 80,
            borderRadius: 16,
            background: fnKeyPressed
              ? "linear-gradient(135deg, #667eea 0%, #764ba2 100%)"
              : "rgba(255, 255, 255, 0.1)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 28,
            fontWeight: 600,
            color: "#fff",
            boxShadow: fnKeyPressed
              ? "0 0 40px rgba(102, 126, 234, 0.6)"
              : "none",
            border: fnKeyPressed ? "none" : "1px solid rgba(255,255,255,0.2)",
            transition: "all 0.3s",
          }}
        >
          Fn
        </div>
        <span
          style={{
            fontSize: 24,
            color: colors.textMuted,
            fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
          }}
        >
          {fnKeyPressed ? "正在聆听..." : "长按开始"}
        </span>
      </div>

      {/* 声波可视化 */}
      {fnKeyPressed && (
        <div
          style={{
            position: "absolute",
            bottom: 400,
            display: "flex",
            alignItems: "center",
            gap: 6,
          }}
        >
          {[...Array(20)].map((_, i) => {
            const height = interpolate(
              Math.sin((frame + i * 8) * 0.25),
              [-1, 1],
              [15, 60]
            );
            const opacity = interpolate(
              Math.abs(i - 10),
              [0, 10],
              [1, 0.3]
            );
            return (
              <div
                key={i}
                style={{
                  width: 4,
                  height,
                  background: `rgba(102, 126, 234, ${opacity})`,
                  borderRadius: 2,
                }}
              />
            );
          })}
        </div>
      )}
    </AbsoluteFill>
  );
};

// 场景3：文字快速输出
const Scene3_FastOutput: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const fullText = "语音转文字，快如闪电";

  // 更快的打字速度 - 30帧内完成
  const typedLength = Math.floor(
    interpolate(frame, [10, 40], [0, fullText.length], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    })
  );
  const displayText = fullText.slice(0, typedLength);

  const inputOpacity = interpolate(frame, [0, 15], [0, 1], {
    extrapolateRight: "clamp",
  });

  const speedBadgeOpacity = interpolate(frame, [50, 65], [0, 1], {
    extrapolateRight: "clamp",
  });

  const speedBadgeScale = spring({
    frame: frame - 50,
    fps,
    config: { damping: 10 },
  });

  // HUD 从录音切换到处理
  const hudState = frame < 35 ? "recording" : "processing";
  const hudOpacity = interpolate(frame, [60, 75], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: colors.background,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <SmokeEffect intensity={0.8} />

      {/* HUD */}
      <div
        style={{
          position: "absolute",
          top: 150,
          opacity: hudOpacity,
        }}
      >
        <HUD state={hudState} frame={frame} />
      </div>

      {/* 输入区域 */}
      <div style={{ opacity: inputOpacity }}>
        <InputArea text={displayText} showCursor={frame < 70} />
      </div>

      {/* 速度徽章 */}
      <div
        style={{
          position: "absolute",
          bottom: 200,
          opacity: speedBadgeOpacity,
          transform: `scale(${Math.max(0, speedBadgeScale)})`,
          display: "flex",
          alignItems: "center",
          gap: 12,
        }}
      >
        <span style={{ fontSize: 48 }}>⚡</span>
        <span
          style={{
            fontSize: 28,
            fontWeight: 600,
            color: colors.text,
            fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
          }}
        >
          本地处理，极速响应
        </span>
      </div>
    </AbsoluteFill>
  );
};

// 场景4：特性展示
const Scene4_Features: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const features = [
    { icon: "lock.png", title: "100% 本地", desc: "隐私安全" },
    { icon: "high-voltage.png", title: "极速识别", desc: "毫秒响应" },
    { icon: "globe-with-meridians.png", title: "中英混合", desc: "智能切换" },
  ];

  return (
    <AbsoluteFill
      style={{
        background: colors.background,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <SmokeEffect intensity={0.7} />

      <div style={{ display: "flex", gap: 80 }}>
        {features.map((feature, index) => {
          const delay = index * 12;
          const opacity = interpolate(frame - delay, [0, 20], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          });
          const y = interpolate(frame - delay, [0, 20], [40, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          });

          return (
            <div
              key={index}
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                opacity,
                transform: `translateY(${y}px)`,
              }}
            >
              <div
                style={{
                  width: 120,
                  height: 120,
                  borderRadius: 30,
                  background: "rgba(255, 255, 255, 0.08)",
                  border: "1px solid rgba(255, 255, 255, 0.15)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  marginBottom: 24,
                }}
              >
                <Img
                  src={staticFile(feature.icon)}
                  style={{
                    width: 72,
                    height: 72,
                  }}
                />
              </div>
              <h3
                style={{
                  fontSize: 28,
                  fontWeight: 600,
                  color: colors.text,
                  margin: 0,
                  marginBottom: 8,
                  fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
                }}
              >
                {feature.title}
              </h3>
              <p
                style={{
                  fontSize: 18,
                  color: colors.textMuted,
                  margin: 0,
                  fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
                }}
              >
                {feature.desc}
              </p>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// 场景5：结尾 CTA
const Scene5_CTA: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const titleOpacity = interpolate(frame, [0, 20], [0, 1], {
    extrapolateRight: "clamp",
  });

  const titleScale = spring({
    frame,
    fps,
    config: { damping: 12 },
  });

  const commandOpacity = interpolate(frame, [30, 50], [0, 1], {
    extrapolateRight: "clamp",
  });

  const commandY = interpolate(frame, [30, 50], [20, 0], {
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: colors.background,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <SmokeEffect intensity={0.9} />

      {/* Logo 小版 */}
      <Img
        src={staticFile("icon_512x512.png")}
        style={{
          width: 80,
          height: 80,
          borderRadius: 20,
          marginBottom: 30,
          opacity: titleOpacity,
          transform: `scale(${titleScale})`,
          boxShadow: "0 10px 40px rgba(102, 126, 234, 0.3)",
        }}
      />

      <h1
        style={{
          fontSize: 72,
          fontWeight: 700,
          color: colors.text,
          opacity: titleOpacity,
          transform: `scale(${titleScale})`,
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif",
          letterSpacing: "-1px",
          margin: 0,
          marginBottom: 50,
        }}
      >
        nano typeless
      </h1>

      {/* 安装命令 */}
      <div
        style={{
          opacity: commandOpacity,
          transform: `translateY(${commandY}px)`,
          background: "rgba(255, 255, 255, 0.05)",
          borderRadius: 12,
          padding: "20px 40px",
          border: "1px solid rgba(255, 255, 255, 0.1)",
          display: "flex",
          flexDirection: "column",
          gap: 8,
        }}
      >
        <code
          style={{
            fontSize: 22,
            color: "#10b981",
            fontFamily: "SF Mono, Menlo, monospace",
          }}
        >
          brew tap ZhaoChaoqun/typeless
        </code>
        <code
          style={{
            fontSize: 22,
            color: "#10b981",
            fontFamily: "SF Mono, Menlo, monospace",
          }}
        >
          brew install --cask nano-typeless
        </code>
      </div>

      {/* GitHub */}
      <p
        style={{
          fontSize: 18,
          color: colors.textMuted,
          marginTop: 40,
          opacity: commandOpacity,
          fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
        }}
      >
        github.com/ZhaoChaoqun/typeless
      </p>
    </AbsoluteFill>
  );
};

// 主视频组件
export const TypelessPromo: React.FC = () => {
  const { width } = useVideoConfig();
  // 根据实际分辨率计算缩放比例（以 1920 为基准）
  const scale = width / 1920;

  return (
    <AbsoluteFill style={{ background: colors.background }}>
      {/* 背景音乐 */}
      <Audio
        src={staticFile("mehul-choudhary-effortless.mp3")}
        volume={0.25}
        startFrom={0}
      />

      {/* 旁白：场景1 - nano typeless，按下即说 */}
      <Sequence from={30}>
        <Audio src={staticFile("vo1.m4a")} volume={1} />
      </Sequence>

      {/* 旁白：场景2 - 一键呼出语音输入 */}
      <Sequence from={100}>
        <Audio src={staticFile("vo2.m4a")} volume={1} />
      </Sequence>

      {/* 旁白：场景3 - 极速转录，所说即所得 */}
      <Sequence from={190}>
        <Audio src={staticFile("vo3.m4a")} volume={1} />
      </Sequence>

      {/* 旁白：场景4 - 完全本地运行，隐私无忧 */}
      <Sequence from={290}>
        <Audio src={staticFile("vo4.m4a")} volume={1} />
      </Sequence>

      {/* 旁白：场景5 - 立即下载，开启语音输入新体验 */}
      <Sequence from={420}>
        <Audio src={staticFile("vo5.m4a")} volume={1} />
      </Sequence>

      {/* 内容容器 - 根据分辨率自动缩放 */}
      <AbsoluteFill
        style={{
          transform: `scale(${scale})`,
          transformOrigin: "top left",
          width: 1920,
          height: 1080,
        }}
      >
        {/* 场景1：开场 0-90帧 (3秒) */}
        <Sequence from={0} durationInFrames={90}>
          <Scene1_Intro />
        </Sequence>

        {/* 场景2：录音演示 90-180帧 (3秒) */}
        <Sequence from={90} durationInFrames={90}>
          <Scene2_Recording />
        </Sequence>

        {/* 场景3：快速输出 180-270帧 (3秒) */}
        <Sequence from={180} durationInFrames={90}>
          <Scene3_FastOutput />
        </Sequence>

        {/* 场景4：特性展示 270-390帧 (4秒) */}
        <Sequence from={270} durationInFrames={120}>
          <Scene4_Features />
        </Sequence>

        {/* 场景5：结尾 CTA 390-540帧 (5秒) */}
        <Sequence from={390} durationInFrames={150}>
          <Scene5_CTA />
        </Sequence>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
