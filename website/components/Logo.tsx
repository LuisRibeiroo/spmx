import Image from "next/image";
import Link from "next/link";

export function Logo({ size = 28 }: { size?: number }) {
  return (
    <Link href="/" className="inline-flex min-h-10 shrink-0 items-center gap-2.5 font-semibold tracking-tight">
      <Image
        src="/icon.svg"
        alt=""
        width={size}
        height={Math.round((size * 48) / 41)}
        unoptimized
        className="[image-rendering:pixelated]"
      />
      <span className="font-mono text-base">spmx</span>
    </Link>
  );
}
