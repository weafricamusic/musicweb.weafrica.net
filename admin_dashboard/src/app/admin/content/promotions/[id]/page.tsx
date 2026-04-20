import EditPromotionClient from './EditPromotionClient'

type Params = { id: string }

export default async function EditPromotionPage({ params }: { params: Promise<Params> }) {
	const resolved = await params
	return <EditPromotionClient promotionId={String(resolved?.id ?? '')} />
}
