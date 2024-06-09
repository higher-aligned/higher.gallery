import { Box, Card, Flex, Grid, Text } from '@radix-ui/themes'
import Image from 'next/image'
import { notFound } from 'next/navigation'
import { z } from 'zod'
import { PageContainer } from '@/components/container'
import { Name } from '@/components/name'
import { ponderClient } from '@/lib/ponder'
import { NextPageContext } from '@/lib/types/next'
import { formatIpfsUri } from '@/lib/utils/ipfs'
import { address as addressSchema } from '@/lib/zod/address'
import { Activity } from './activity'
import { MintSection } from './mint-section'
import styles from './page.module.css'

export const revalidate = 86400 // One day in seconds

const schema = z.object({
  address: addressSchema,
  id: z.string().pipe(z.coerce.bigint().positive()),
})

export default async function TokenPage({ params }: NextPageContext) {
  const parseResult = schema.safeParse(params)
  if (!parseResult.success) notFound()
  const { address, id } = parseResult.data

  const { token } = await ponderClient.token({
    token: `${address}-${id.toString()}`,
  })

  if (!token) notFound()

  return (
    <PageContainer>
      <Grid
        rows={{ initial: 'auto auto', sm: '1' }}
        columns={{ initial: '1', sm: '2' }}
        gap="4"
      >
        <Box asChild maxHeight="600px" maxWidth="100%" mx="auto">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={formatIpfsUri(token.image, 1000)} alt="Token image" />
        </Box>
        <Flex direction="column" gap="4">
          <Card>
            <Text as="div" size="5" weight="medium" mb="1">
              {token.name}
            </Text>
            <Flex direction="row" gap="2">
              <Box asChild width="48px" height="48px" overflow="hidden">
                <Image
                  src={formatIpfsUri(token.collection.image)}
                  alt="Collection image"
                  className={styles.collection}
                  width="48"
                  height="48"
                />
              </Box>
              <Flex direction="column" gap="1">
                <Text as="div" size="3" weight="medium">
                  <Name
                    address={addressSchema.parse(
                      token.collection.creatorAddress,
                    )}
                  />
                </Text>
                <Text as="div" size="3" color="gray">
                  {token.collection.name}
                </Text>
              </Flex>
            </Flex>
          </Card>
          <MintSection token={token} />
          <Activity token={token} />
        </Flex>
      </Grid>
    </PageContainer>
  )
}
