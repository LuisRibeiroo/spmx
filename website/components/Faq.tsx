export interface FaqItem {
  q: string;
  a: React.ReactNode;
}

/** Native <details>: keyboard accessible and works without JavaScript. */
export function Faq({ items }: { items: FaqItem[] }) {
  return (
    <div data-faq="" className="divide-y divide-line border-y border-line">
      {items.map((item) => (
        <details key={item.q} className="group py-1">
          <summary className="flex min-h-12 cursor-pointer list-none items-center justify-between gap-4 py-3 text-left font-medium [&::-webkit-details-marker]:hidden">
            <span>{item.q}</span>
            <svg
              className="shrink-0 text-ink-muted transition-transform duration-200 ease-out group-open:rotate-45 motion-reduce:transition-none"
              width="16"
              height="16"
              viewBox="0 0 16 16"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
              aria-hidden="true"
            >
              <path d="M8 2v12M2 8h12" />
            </svg>
          </summary>
          <div className="max-w-[65ch] pb-4 text-[0.9375rem] leading-relaxed text-ink-muted">{item.a}</div>
        </details>
      ))}
    </div>
  );
}
