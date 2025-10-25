import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { useCurrentAccount, useSignAndExecuteTransactionBlock } from '@mysten/dapp-kit';
import { TransactionBlock } from '@mysten/sui.js/transactions';
import { projectService } from '../services/api';
import { Project } from '../types';

const ProjectDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const [project, setProject] = useState<Project | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [donationAmount, setDonationAmount] = useState<string>('');
  const [donating, setDonating] = useState(false);

  const currentAccount = useCurrentAccount();
  const { mutate: signAndExecute } = useSignAndExecuteTransactionBlock();

  useEffect(() => {
    const fetchProject = async () => {
      if (!id) return;
      
      try {
        const projectData = await projectService.getProject(id);
        setProject(projectData);
      } catch (err) {
        setError('無法載入項目詳情');
        console.error('Error fetching project:', err);
      } finally {
        setLoading(false);
      }
    };

    fetchProject();
  }, [id]);

  const handleDonate = async () => {
    if (!project || !currentAccount || !donationAmount) return;

    setDonating(true);
    try {
      const amount = parseFloat(donationAmount) * 1000000000; // Convert SUI to MIST
      
      const txb = new TransactionBlock();
      const [coin] = txb.splitCoins(txb.gas, [txb.pure(amount)]);
      
      // =======================================================================
      // TODO: 將 '0x0' 替換部署後的真實 Package ID
      // 例如: target: '0x123abc...def::bluelink::donate'
      // =======================================================================
      txb.moveCall({
        target: '0x0::bluelink::donate', // Replace with actual package address
        arguments: [
          txb.object(project.id),
          coin,
        ],
      });

      signAndExecute(
        { transactionBlock: txb },
        {
          onSuccess: (result) => {
            console.log('Donation successful:', result);
            setDonationAmount('');
            // Refresh project data
            window.location.reload();
          },
          onError: (error) => {
            console.error('Donation failed:', error);
            alert('捐贈失敗，請重試');
          }
        }
      );
    } catch (err) {
      console.error('Error creating donation transaction:', err);
      alert('建立交易失敗，請重試');
    } finally {
      setDonating(false);
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center min-h-64">
        <div className="text-lg">正在載入項目詳情...</div>
      </div>
    );
  }

  if (error || !project) {
    return (
      <div className="flex justify-center items-center min-h-64">
        <div className="text-red-600 text-lg">{error || '項目不存在'}</div>
      </div>
    );
  }

  const fundingGoal = parseFloat(project.funding_goal) / 1000000000;
  const totalRaised = parseFloat(project.total_raised) / 1000000000;
  const progressPercentage = fundingGoal > 0 ? (totalRaised / fundingGoal) * 100 : 0;

  return (
    <div className="max-w-4xl mx-auto">
      <div className="bg-white rounded-lg shadow-lg overflow-hidden">
        <div className="p-8">
          <div className="flex justify-between items-start mb-6">
            <h1 className="text-3xl font-bold text-gray-800">{project.name}</h1>
            <div className="text-sm text-gray-500">
              項目 ID: {project.id.substring(0, 8)}...
            </div>
          </div>

          <div className="mb-8">
            <h2 className="text-xl font-semibold mb-3">項目描述</h2>
            <p className="text-gray-600 leading-relaxed">{project.description}</p>
          </div>

          <div className="mb-8">
            <div className="flex justify-between items-center mb-3">
              <h2 className="text-xl font-semibold">募款進度</h2>
              <span className="text-lg font-bold text-blue-600">
                {progressPercentage.toFixed(1)}%
              </span>
            </div>
            <div className="w-full bg-gray-200 rounded-full h-4 mb-4">
              <div 
                className="bg-blue-600 h-4 rounded-full transition-all duration-300" 
                style={{ width: `${Math.min(progressPercentage, 100)}%` }}
              ></div>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <div className="text-center">
                <div className="text-2xl font-bold text-blue-600">
                  {totalRaised.toFixed(2)} SUI
                </div>
                <div className="text-sm text-gray-600">已募集</div>
              </div>
              <div className="text-center">
                <div className="text-2xl font-bold text-gray-800">
                  {fundingGoal.toFixed(2)} SUI
                </div>
                <div className="text-sm text-gray-600">目標金額</div>
              </div>
              <div className="text-center">
                <div className="text-2xl font-bold text-green-600">
                  {project.donor_count}
                </div>
                <div className="text-sm text-gray-600">捐贈者</div>
              </div>
            </div>
          </div>

          {currentAccount ? (
            <div className="bg-gray-50 rounded-lg p-6">
              <h3 className="text-lg font-semibold mb-4">支持此項目</h3>
              <div className="flex space-x-4">
                <input
                  type="number"
                  placeholder="輸入捐贈金額 (SUI)"
                  value={donationAmount}
                  onChange={(e) => setDonationAmount(e.target.value)}
                  className="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
                  step="0.1"
                  min="0.1"
                />
                <button
                  onClick={handleDonate}
                  disabled={donating || !donationAmount || parseFloat(donationAmount) <= 0}
                  className="bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {donating ? '處理中...' : '捐贈'}
                </button>
              </div>
              <p className="text-sm text-gray-600 mt-2">
                最少捐贈 0.1 SUI。您的捐贈將獲得一個鏈上數位憑證作為證明。
              </p>
            </div>
          ) : (
            <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-6 text-center">
              <p className="text-yellow-800 mb-4">請連接錢包以支持此項目</p>
              <div className="text-sm text-yellow-700">
                連接錢包後，您可以直接在此頁面進行捐贈
              </div>
            </div>
          )}

          <div className="mt-8 pt-6 border-t border-gray-200">
            <h3 className="text-lg font-semibold mb-2">項目建立者</h3>
            <div className="text-sm text-gray-600 font-mono">
              {project.creator}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ProjectDetailPage;
