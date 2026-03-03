/**
 * riskScore.groovy
 * Jenkins Shared Library step — AI Risk Scoring integration.
 *
 * Calls the Python inference script, parses the JSON report,
 * records build metadata, and returns the risk assessment map.
 *
 * Usage in Jenkinsfile:
 *   def report = riskScore.evaluate(
 *       buildNumber   : env.BUILD_NUMBER,
 *       commit        : env.GIT_COMMIT,
 *       changedFiles  : env.CHANGED_FILES,
 *       commitMessage : env.GIT_COMMIT_MSG,
 *       coverage      : env.CODE_COVERAGE,
 *       criticalVulns : env.CRITICAL_VULNS,
 *       riskThreshold : 0.7,
 *       outputFile    : 'risk-score.json'
 *   )
 *   echo "Risk level: ${report.risk_level}"
 */

/**
 * Evaluate build risk using the ML inference engine.
 *
 * @param config Map with the following optional keys:
 *   buildNumber    (int)    - Jenkins build number
 *   commit         (String) - Git commit SHA
 *   changedFiles   (int)    - Number of changed files
 *   commitMessage  (String) - Git commit message
 *   coverage       (float)  - Code coverage %
 *   criticalVulns  (int)    - Critical vulnerability count
 *   testCount      (int)    - Total test count
 *   riskThreshold  (float)  - Score above which human approval is required (default: 0.7)
 *   outputFile     (String) - Path to write JSON report (default: risk-score.json)
 *   modelPath      (String) - Path to trained model pkl (default: models/risk_model.pkl)
 *   requireApproval (bool)  - Whether to pause pipeline on HIGH risk (default: true)
 *
 * @return Map parsed from risk-score.json with keys:
 *   risk_score, risk_level, risk_emoji, predicted_failure,
 *   predicted_failure_reason, recommended_actions, etc.
 */
def evaluate(Map config = [:]) {
    def buildNumber   = config.get('buildNumber',   env.BUILD_NUMBER   ?: '0')
    def commit        = config.get('commit',         env.GIT_COMMIT     ?: 'unknown')
    def changedFiles  = config.get('changedFiles',   env.CHANGED_FILES  ?: '5')
    def commitMessage = config.get('commitMessage',  env.GIT_COMMIT_MSG ?: '')
    def coverage      = config.get('coverage',       env.CODE_COVERAGE  ?: '0')
    def criticalVulns = config.get('criticalVulns',  env.CRITICAL_VULNS ?: '0')
    def testCount     = config.get('testCount',      '50')
    def riskThreshold = config.get('riskThreshold',  0.7)
    def outputFile    = config.get('outputFile',     'risk-score.json')
    def modelPath     = config.get('modelPath',      'models/risk_model.pkl')
    def requireApproval = config.get('requireApproval', true)

    // ── Run inference ──────────────────────────────────────────────────────
    sh """
        python src/inference.py \\
            --build-number ${buildNumber} \\
            --commit ${commit} \\
            --changed-files ${changedFiles} \\
            --commit-message "${commitMessage.replace('"', '\\"')}" \\
            --coverage ${coverage} \\
            --critical-vulns ${criticalVulns} \\
            --test-count ${testCount} \\
            --model-path ${modelPath} \\
            --output ${outputFile}
    """

    // ── Parse report ──────────────────────────────────────────────────────
    def report = readJSON file: outputFile

    def riskScore = report.risk_score as float
    def riskLevel = report.risk_level
    def riskEmoji = report.risk_emoji ?: '⚪'

    // ── Persist as build environment variables ────────────────────────────
    env.RISK_SCORE             = riskScore.toString()
    env.RISK_LEVEL             = riskLevel
    env.PREDICTED_FAILURE      = report.predicted_failure.toString()
    env.PREDICTED_FAILURE_REASON = report.predicted_failure_reason ?: ''

    // ── Print formatted report ────────────────────────────────────────────
    _printReport(report)

    // ── Archive artifact ──────────────────────────────────────────────────
    archiveArtifacts artifacts: outputFile, fingerprint: true

    // ── Record build description ──────────────────────────────────────────
    currentBuild.description = "${riskEmoji} Risk: ${riskLevel} (${riskScore})"

    // ── High-risk gate ────────────────────────────────────────────────────
    if (requireApproval && riskScore >= riskThreshold) {
        _handleHighRisk(report, riskScore, riskThreshold)
    }

    return report
}

/**
 * Compute a risk score without triggering any gate logic.
 * Useful for informational dashboards or audit trails.
 *
 * @param config Same keys as evaluate()
 * @return Parsed risk report Map
 */
def scoreOnly(Map config = [:]) {
    return evaluate(config + [requireApproval: false])
}

// ── Private helpers ────────────────────────────────────────────────────────────

private def _printReport(def report) {
    def score = report.risk_score
    def level = report.risk_level
    def emoji = report.risk_emoji ?: ''
    def reason = report.predicted_failure_reason ?: 'N/A'

    echo """
╔══════════════════════════════════════════════════╗
║          AI RISK ASSESSMENT REPORT               ║
╠══════════════════════════════════════════════════╣
║  Risk Score  : ${String.format('%-33s', score.toString() + '  ' + emoji)} ║
║  Risk Level  : ${String.format('%-33s', level)} ║
║  Prediction  : ${String.format('%-33s', report.predicted_failure.toString())} ║
║  Reason      : ${String.format('%-33s', reason.take(33))} ║
╠══════════════════════════════════════════════════╣
║  Recommendations:                                ║"""

    def recs = report.recommended_actions ?: ['No recommendations']
    recs.each { rec ->
        def truncated = rec.toString().take(46)
        echo "║  ${truncated.padRight(48)}║"
    }

    echo """╚══════════════════════════════════════════════════╝
"""
}

private def _handleHighRisk(def report, float score, float threshold) {
    def reason  = report.predicted_failure_reason ?: 'Multiple risk factors detected'
    def recs    = (report.recommended_actions ?: []).join('\n  - ')

    echo """
⚠️  HIGH RISK DETECTED
   Score     : ${score}  (threshold: ${threshold})
   Reason    : ${reason}
   Actions   :
   - ${recs}
"""

    // Pause pipeline and require explicit human confirmation
    timeout(time: 30, unit: 'MINUTES') {
        input(
            message: """🚨 AI Risk Score: ${score} (HIGH)

Reason: ${reason}

Do you want to proceed with deployment?""",
            ok: 'Deploy Anyway',
            submitter: 'jenkins-approvers'
        )
    }
}

return this
