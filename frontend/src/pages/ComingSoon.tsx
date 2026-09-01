export default function ComingSoon({
  title,
  description,
}: {
  title: string
  description: string
}) {
  return (
    <div className="flex flex-col items-start justify-center min-h-[55vh]">
      <div className="text-xs text-accent uppercase tracking-[0.3em] mb-4">Próximamente</div>
      <h1 className="font-display text-5xl lg:text-6xl mb-4 leading-[1.02] tracking-tight">
        {title}
      </h1>
      <p className="text-muted max-w-md text-lg leading-relaxed">{description}</p>
      <div aria-hidden className="mt-8 h-px w-24 bg-accent/50" />
    </div>
  )
}
