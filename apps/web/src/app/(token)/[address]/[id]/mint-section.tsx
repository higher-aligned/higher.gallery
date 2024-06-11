'use client'

import * as Form from '@radix-ui/react-form'
import { ExternalLinkIcon } from '@radix-ui/react-icons'
import {
  Box,
  Button,
  ButtonProps,
  Flex,
  Link as RadixLink,
  Text,
  TextField,
} from '@radix-ui/themes'
import dayjs from 'dayjs'
import relativeTime from 'dayjs/plugin/relativeTime'
import Link from 'next/link'
import {
  ChangeEvent,
  FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from 'react'
import { Signature } from 'viem'
import { useAccount, useBalance, useEstimateGas, usePublicClient } from 'wagmi'
import { ApproveDialog } from '@/app/(token)/[address]/[id]/approve-dialog'
import { chain, env } from '@/env'
import { TokenQuery } from '@/generated/ponder'
import {
  iHigher1155FactoryAddress,
  useReadErc20PermitAllowance,
  useReadErc20PermitBalanceOf,
  useWriteHigher1155ApproveAndMint,
  useWriteHigher1155Mint,
} from '@/generated/wagmi'
import { UINT256_MAX } from '@/lib/constants'
import { useMints } from '@/lib/hooks/mints'
import { address as addressSchema } from '@/lib/zod/address'

dayjs.extend(relativeTime)

type MintButtonProps = {
  token: NonNullable<TokenQuery['token']>
}

export type ApproveParams = Signature & {
  deadline: bigint
}

export function MintSection({ token }: MintButtonProps) {
  const client = usePublicClient()
  const account = useAccount()

  const [amount, setAmount] = useState<bigint | ''>(1n)
  const [comment, setComment] = useState('')
  const [approveDialogOpen, setApproveDialogOpen] = useState(false)

  const handleAmountChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      try {
        if (event.target.value === '') setAmount('')
        else setAmount(BigInt(event.target.value))
      } catch {
        // Do nothing if value is invalid
      }
    },
    [],
  )

  const handleCommentChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      setComment(event.target.value)
    },
    [],
  )

  const mintEndTime = useMemo(
    () => token.endTimestamp && new Date(Number(token.endTimestamp) * 1000),
    [token.endTimestamp],
  )
  const [mintEnded, setMintEnded] = useState(
    !!mintEndTime && mintEndTime < new Date(),
  )
  const [timeRemaining, setTimeRemaining] = useState(
    mintEndTime && !mintEnded && dayjs(mintEndTime).fromNow(true),
  )

  useEffect(() => {
    if (!mintEndTime) return

    const interval = setInterval(() => {
      setTimeRemaining(!mintEnded && dayjs(mintEndTime).fromNow(true))
      setMintEnded(mintEndTime < new Date())
    }, 1000)

    return () => {
      clearInterval(interval)
    }
  }, [mintEndTime, mintEnded])

  const mints = useMints(token)

  const { data: balance } = useReadErc20PermitBalanceOf({
    args: [account.address ?? '0x'],
    query: {
      enabled: account.status === 'connected',
    },
  })
  const { data: allowance } = useReadErc20PermitAllowance({
    args: [account.address ?? '0x', iHigher1155FactoryAddress[chain.id]],
    query: {
      enabled: account.status === 'connected',
    },
  })
  const { data: gasEstimate } = useEstimateGas()
  const { data: ethBalance } = useBalance({
    address: account.address ?? '0x',
    query: {
      enabled: account.status === 'connected',
    },
  })

  const {
    writeContractAsync: approveAndMint,
    isPending: approveAndMintPending,
  } = useWriteHigher1155ApproveAndMint()
  const { writeContractAsync: mint, isPending: mintPending } =
    useWriteHigher1155Mint()

  const handleMint = useCallback(
    (approveParams?: ApproveParams) => {
      async function execute() {
        if (!client) {
          alert('Error getting client')
          return
        }

        if (account.status !== 'connected') {
          alert('Error getting connected account')
          return
        }

        if (approveParams) {
          if (approveParams.v === undefined) {
            alert('Invalid signature')
            return
          }

          await approveAndMint({
            address: addressSchema.parse(token.collection.id),
            args: [
              account.address,
              iHigher1155FactoryAddress[chain.id],
              UINT256_MAX,
              approveParams.deadline,
              Number(approveParams.v),
              approveParams.r,
              approveParams.s,
              BigInt(token.tokenId),
              BigInt(amount),
              comment,
            ],
          })
        } else {
          await mint({
            address: addressSchema.parse(token.collection.id),
            args: [BigInt(token.tokenId), BigInt(amount), comment],
          })
        }

        alert('Minted!')
      }

      void execute()
    },
    [client, account, approveAndMint, mint, token, amount, comment],
  )

  const hasSufficientBalance = useMemo(
    () =>
      balance !== undefined
        ? balance >= BigInt(token.price) * (amount || 0n)
        : undefined,
    [balance, token.price, amount],
  )

  const hasSufficientApproval = useMemo(
    () =>
      allowance !== undefined
        ? allowance >= BigInt(token.price) * (amount || 0n)
        : undefined,
    [allowance, token.price, amount],
  )

  const hasSufficientGas = useMemo(
    () =>
      ethBalance !== undefined && gasEstimate !== undefined
        ? ethBalance.value >= gasEstimate
        : undefined,
    [ethBalance, gasEstimate],
  )

  const handleSubmit = useCallback(
    (event: FormEvent<HTMLFormElement>) => {
      event.preventDefault()

      if (hasSufficientApproval === undefined) {
        alert('Unable to check token approval')
        return
      }

      if (!hasSufficientApproval) {
        setApproveDialogOpen(true)
        return
      }

      handleMint()
    },
    [hasSufficientApproval, handleMint],
  )

  return (
    <Flex direction="column" gap="3">
      <Flex asChild direction="column" gap="3">
        <Form.Root onSubmit={handleSubmit}>
          <Form.Field name="amount">
            <Text as="div" size="2" mb="1" weight="bold">
              Amount
            </Text>
            <Form.Control asChild>
              <TextField.Root
                type="number"
                inputMode="numeric"
                placeholder="Number of editions to mint"
                value={amount.toString()}
                onChange={handleAmountChange}
                min="1"
                required
              />
            </Form.Control>
            <Form.Message asChild match="valueMissing">
              <Text as="div" size="2" mt="1" color="red">
                Please enter an amount
              </Text>
            </Form.Message>
            <Form.Message asChild match="rangeUnderflow">
              <Text as="div" size="2" mt="1" color="red">
                Invalid amount
              </Text>
            </Form.Message>
          </Form.Field>

          <Form.Field name="comment">
            <Form.Control asChild>
              <TextField.Root
                placeholder="Add a comment"
                value={comment}
                onChange={handleCommentChange}
              />
            </Form.Control>
          </Form.Field>

          {hasSufficientBalance === false && (
            <Flex asChild align="center" gap="1">
              <RadixLink asChild>
                <Link
                  href={
                    env.NEXT_PUBLIC_VERCEL_ENV === 'production'
                      ? 'https://app.uniswap.org/swap?chain=base&inputCurrency=ETH&outputCurrency=0x0578d8A44db98B23BF096A382e016e29a5Ce0ffe'
                      : 'https://sepolia.basescan.org/address/0x2499426138486d85b7e145e0057c42ed74af1512#writeContract#F2'
                  }
                  target="_blank"
                >
                  Get $HIGHER <ExternalLinkIcon />
                </Link>
              </RadixLink>
            </Flex>
          )}

          <Box asChild width="100%">
            <Form.Submit asChild>
              <Button
                size="3"
                loading={
                  typeof window === 'undefined' ||
                  account.status === 'connecting' ||
                  account.status === 'reconnecting' ||
                  (account.status === 'connected' &&
                    (balance === undefined ||
                      hasSufficientApproval === undefined ||
                      hasSufficientGas === undefined)) ||
                  (!!token.maxSupply && !mints) ||
                  approveAndMintPending ||
                  mintPending
                }
                {...getButtonProps(
                  mintEnded,
                  !!token.maxSupply &&
                    !!mints &&
                    BigInt(mints.count) + (amount || 0n) >=
                      BigInt(token.maxSupply),
                  account.status === 'connected',
                  hasSufficientBalance,
                  hasSufficientGas,
                  hasSufficientApproval,
                )}
              />
            </Form.Submit>
          </Box>
        </Form.Root>
      </Flex>

      <Text align="center" color="gray" size="1">
        {(!!timeRemaining || mintEnded) && (
          <>
            {timeRemaining && <Text>{timeRemaining} remaining</Text>}
            {mintEnded && <Text>Mint ended</Text>}
            <Text> &bull; </Text>
          </>
        )}
        <Text>
          {mints?.count}
          {token.maxSupply && !mintEnded && ` / ${token.maxSupply}`} minted
        </Text>
      </Text>

      <ApproveDialog
        open={approveDialogOpen}
        onOpenChange={setApproveDialogOpen}
        onSuccess={handleMint}
      />
    </Flex>
  )
}

function getButtonProps(
  mintEnded: boolean,
  supplyLimitExceeded: boolean,
  connected: boolean,
  hasSufficientBalance: boolean | undefined,
  hasSufficientGas: boolean | undefined,
  hasSufficientApproval: boolean | undefined,
): ButtonProps {
  if (mintEnded)
    return {
      disabled: true,
      children: 'Mint ended',
    }

  if (supplyLimitExceeded)
    return {
      disabled: true,
      children: 'Max supply exceeded',
    }

  if (!connected)
    return {
      disabled: true,
      children: 'Connect wallet to mint',
    }

  if (hasSufficientBalance === false)
    return {
      disabled: true,
      children: 'Insufficient $HIGHER balance',
    }

  if (hasSufficientGas === false)
    return {
      disabled: true,
      children: 'Insufficient ETH for gas',
    }

  if (hasSufficientApproval === false)
    return {
      children: 'Approve and mint',
    }

  return {
    children: 'Mint',
  }
}
