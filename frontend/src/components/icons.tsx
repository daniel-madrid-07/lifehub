import type { SVGProps } from "react"

function Base({ children, ...props }: SVGProps<SVGSVGElement>) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...props}
    >
      {children}
    </svg>
  )
}

export function PulseIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M12 20.5S4.5 15.6 2.8 11C1.6 7.6 4 4.5 7.2 4.5c2 0 3.7 1.2 4.8 3 1.1-1.8 2.8-3 4.8-3 3.2 0 5.6 3.1 4.4 6.5-1.7 4.6-9.2 9.5-9.2 9.5z" />
      <path d="M7 12h2.5l1.5-3 2 5 1.5-2H17" />
    </Base>
  )
}

export function BowlIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M4 12.5h16a8 8 0 0 1-16 0z" />
      <path d="M7.5 20h9" />
      <path d="M9.5 9c0-1.4 1.2-1.6 1.2-3M14 9c0-1.4 1.2-1.6 1.2-3" />
    </Base>
  )
}

export function CoinsIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <circle cx="12" cy="12" r="8.5" />
      <path d="M14.8 9.2A3.4 3.4 0 0 0 12.3 8c-2 0-3.5 1.8-3.5 4s1.5 4 3.5 4c1 0 1.9-.45 2.5-1.2" />
      <path d="M7.5 11h4.5M7.5 13.2h4" />
    </Base>
  )
}

export function MailIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <rect x="3" y="5.5" width="18" height="13" rx="2.5" />
      <path d="m4 7.5 8 6 8-6" />
    </Base>
  )
}

export function CalendarIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <rect x="3.5" y="5" width="17" height="15.5" rx="2.5" />
      <path d="M3.5 10h17M8.5 3v4M15.5 3v4" />
    </Base>
  )
}

export function CapIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M2.5 9.5 12 4.5l9.5 5L12 14.5l-9.5-5z" />
      <path d="M6.5 12v4.2c0 1.4 2.5 2.8 5.5 2.8s5.5-1.4 5.5-2.8V12" />
      <path d="M21.5 9.5v5" />
    </Base>
  )
}

export function HomeIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M4 11 12 4l8 7" />
      <path d="M5.5 9.5V19a1 1 0 0 0 1 1H10v-5h4v5h3.5a1 1 0 0 0 1-1V9.5" />
    </Base>
  )
}

export function GridIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <rect x="4" y="4" width="6.5" height="6.5" rx="1.6" />
      <rect x="13.5" y="4" width="6.5" height="6.5" rx="1.6" />
      <rect x="4" y="13.5" width="6.5" height="6.5" rx="1.6" />
      <rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.6" />
    </Base>
  )
}

export function ChecklistIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="m3.5 7 1.5 1.5L8 5.5M3.5 16l1.5 1.5L8 14.5M11 7.5h9.5M11 16.5h9.5" />
    </Base>
  )
}

export function CameraIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M3.5 8.5a2 2 0 0 1 2-2h1.2l1-1.6h6.6l1 1.6h1.2a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z" />
      <circle cx="12" cy="12.5" r="3.2" />
    </Base>
  )
}

export function RulerIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M4 14.5 14.5 4l5.5 5.5L9.5 20z" />
      <path d="M8 8.5l2 2M11 5.5l2 2M5.5 11l2 2M14 13l2 2" />
    </Base>
  )
}

export function DumbbellIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M7.5 7.5v9M4.5 9.5v5M16.5 7.5v9M19.5 9.5v5M7.5 12h9M2.5 12h2M19.5 12h2" />
    </Base>
  )
}

export function PlusIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base strokeWidth="2" {...props}>
      <path d="M12 5v14M5 12h14" />
    </Base>
  )
}

export function RefreshIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M20 12a8 8 0 1 1-2.34-5.66" />
      <path d="M20 4v4.5h-4.5" />
    </Base>
  )
}

export function UndoIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M8.5 5.5 4 10l4.5 4.5" />
      <path d="M4 10h10a5.5 5.5 0 0 1 0 11h-3.5" />
    </Base>
  )
}

export function TrashIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M4 7h16M9.5 7V4.5h5V7M6 7l1 13h10l1-13" />
      <path d="M10 11v5.5M14 11v5.5" />
    </Base>
  )
}

export function PencilIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="m4 20 .8-3.8L16.6 4.4a2 2 0 0 1 2.8 0l.2.2a2 2 0 0 1 0 2.8L7.8 19.2 4 20z" />
    </Base>
  )
}

export function PauseIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M9 5.5v13M15 5.5v13" />
    </Base>
  )
}

export function PlayIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M7.5 5.5v13l10-6.5-10-6.5z" />
    </Base>
  )
}

export function XIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base strokeWidth="2" {...props}>
      <path d="M6 6l12 12M18 6 6 18" />
    </Base>
  )
}

export function CheckIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base strokeWidth="2.5" {...props}>
      <path d="M5 13l4 4L19 7" />
    </Base>
  )
}

export function ChevronUpDownIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base strokeWidth="2" {...props}>
      <path d="m8 9.5 4-4 4 4M8 14.5l4 4 4-4" />
    </Base>
  )
}

export function FlameIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <path d="M12 21c-3.6 0-6.5-2.5-6.5-6.2 0-2.6 1.6-4.6 3-6.3.9-1.1 1.9-2.4 2.3-4 .1-.5.7-.7 1-.3 1.1 1.2 1.6 2.6 1.7 4 .9-.5 1.5-1.2 1.9-2 .2-.4.8-.4 1 0 1.1 2 2.1 4.4 2.1 6.6 0 5.7-2.9 8.2-6.5 8.2z" />
    </Base>
  )
}

export function GearIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <Base {...props}>
      <circle cx="12" cy="12" r="3" />
      <path d="M12 2.5l1.3 2.3 2.6-.5.4 2.6 2.3 1.3-1.1 2.4 1.1 2.4-2.3 1.3-.4 2.6-2.6-.5L12 21.5l-1.3-2.3-2.6.5-.4-2.6-2.3-1.3 1.1-2.4-1.1-2.4 2.3-1.3.4-2.6 2.6.5z" />
    </Base>
  )
}
