import { Composition } from "remotion";
import { TypelessPromo } from "./TypelessPromo";
import { TypelessPromoVertical } from "./TypelessPromoVertical";
import { TypelessPromoV2 } from "./TypelessPromoV2";
import { TypelessPromoV2Vertical } from "./TypelessPromoV2Vertical";
import { TypelessPromoV2_4K } from "./TypelessPromoV2_4K";
import { TypelessPromoV2Vertical4K } from "./TypelessPromoV2Vertical4K";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      {/* V2 横版 4K 3840x2160 - 18.5秒 */}
      <Composition
        id="TypelessPromoV2-4K"
        component={TypelessPromoV2_4K}
        durationInFrames={555}
        fps={30}
        width={3840}
        height={2160}
      />
      {/* V2 竖版 4K 2160x3840 - 18.5秒 */}
      <Composition
        id="TypelessPromoV2Vertical-4K"
        component={TypelessPromoV2Vertical4K}
        durationInFrames={555}
        fps={30}
        width={2160}
        height={3840}
      />
      {/* V2 横版 1080p - 18.5秒 */}
      <Composition
        id="TypelessPromoV2"
        component={TypelessPromoV2}
        durationInFrames={555}
        fps={30}
        width={1920}
        height={1080}
      />
      {/* V2 竖版 1080p - 18.5秒 */}
      <Composition
        id="TypelessPromoV2Vertical"
        component={TypelessPromoV2Vertical}
        durationInFrames={555}
        fps={30}
        width={1080}
        height={1920}
      />
      {/* 旧版 横版 4K */}
      <Composition
        id="TypelessPromo"
        component={TypelessPromo}
        durationInFrames={540}
        fps={30}
        width={3840}
        height={2160}
      />
      {/* 旧版 横版 1080p */}
      <Composition
        id="TypelessPromo1080"
        component={TypelessPromo}
        durationInFrames={540}
        fps={30}
        width={1920}
        height={1080}
      />
      {/* 旧版 竖版 4K */}
      <Composition
        id="TypelessPromoVertical"
        component={TypelessPromoVertical}
        durationInFrames={540}
        fps={30}
        width={2160}
        height={3840}
      />
      {/* 旧版 竖版 1080p */}
      <Composition
        id="TypelessPromoVertical1080"
        component={TypelessPromoVertical}
        durationInFrames={540}
        fps={30}
        width={1080}
        height={1920}
      />
    </>
  );
};
