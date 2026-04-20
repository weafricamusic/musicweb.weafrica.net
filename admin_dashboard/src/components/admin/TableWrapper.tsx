import type { ReactNode } from 'react'

export default function TableWrapper({ children }: { children: ReactNode }) {
	return <div className="w-full overflow-x-auto">{children}</div>
}
