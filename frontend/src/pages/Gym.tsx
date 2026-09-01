import { useState } from "react"
import GymTrain from "./GymTrain"
import GymProgress from "./GymProgress"
import GymHealth from "./GymHealth"
import { Segmented } from "../components/ui"

type Tab = "train" | "progress" | "health"

// Las rutinas se crean/editan en Ajustes; aquí solo se entrena y se consulta.
const TABS: { id: Tab; label: string }[] = [
  { id: "train", label: "Entrenar" },
  { id: "progress", label: "Progreso" },
  { id: "health", label: "Salud" },
]

export default function Gym() {
  const [tab, setTab] = useState<Tab>("train")

  return (
    <div>
      <Segmented tabs={TABS} value={tab} onChange={setTab} label="Secciones de gym" layoutId="gym-pill" />
      {tab === "train" && <GymTrain />}
      {tab === "progress" && <GymProgress />}
      {tab === "health" && <GymHealth />}
    </div>
  )
}
