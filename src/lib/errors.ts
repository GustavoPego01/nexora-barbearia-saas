export type ErrorCode = 'CONFIGURATION' | 'UNAUTHORIZED' | 'VALIDATION' | 'UNEXPECTED'

export class AppError extends Error {
  constructor(public readonly code: ErrorCode, message: string) {
    super(message)
    this.name = 'AppError'
  }
}

/** Não exibe respostas brutas do banco, tokens ou detalhes internos. */
export function getErrorMessage(error: unknown): string {
  return error instanceof AppError
    ? error.message
    : 'Não foi possível concluir a operação. Tente novamente.'
}
