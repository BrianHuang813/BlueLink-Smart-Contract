import React, { useState } from 'react';
import { useCurrentAccount, useSignAndExecuteTransactionBlock } from '@mysten/dapp-kit';
import { TransactionBlock } from '@mysten/sui.js/transactions';
import { CreateProjectForm } from '../types';

const CreateProjectPage: React.FC = () => {
  const [form, setForm] = useState<CreateProjectForm>({
    name: '',
    description: '',
    funding_goal: 0,
  });
  const [creating, setCreating] = useState(false);

  const currentAccount = useCurrentAccount();
  const { mutate: signAndExecute } = useSignAndExecuteTransactionBlock();

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
    setForm(prev => ({
      ...prev,
      [name]: name === 'funding_goal' ? parseFloat(value) || 0 : value,
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!currentAccount || !form.name || !form.description || form.funding_goal <= 0) {
      return;
    }

    setCreating(true);
    try {
      const fundingGoalMist = form.funding_goal * 1000000000; // Convert SUI to MIST
      
      const txb = new TransactionBlock();
      
      // =======================================================================
      // TODO: 將 '0x0' 替換為真實 Package ID
      // 例如: target: '0x123abc...def::bluelink::create_project'
      // =======================================================================
      txb.moveCall({
        target: '0x0::bluelink::create_project', // Replace with actual package address
        arguments: [
          txb.pure(Array.from(new TextEncoder().encode(form.name))),
          txb.pure(Array.from(new TextEncoder().encode(form.description))),
          txb.pure(fundingGoalMist),
        ],
      });

      signAndExecute(
        { transactionBlock: txb },
        {
          onSuccess: (result) => {
            console.log('Project created successfully:', result);
            alert('項目建立成功！');
            setForm({ name: '', description: '', funding_goal: 0 });
          },
          onError: (error) => {
            console.error('Project creation failed:', error);
            alert('項目建立失敗，請重試');
          }
        }
      );
    } catch (err) {
      console.error('Error creating project transaction:', err);
      alert('建立交易失敗，請重試');
    } finally {
      setCreating(false);
    }
  };

  if (!currentAccount) {
    return (
      <div className="max-w-2xl mx-auto">
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-8 text-center">
          <div className="text-6xl mb-4">🔌</div>
          <h2 className="text-2xl font-bold text-yellow-800 mb-2">
            需要連接錢包
          </h2>
          <p className="text-yellow-700 mb-4">
            請先連接您的 Sui 錢包以建立項目
          </p>
          <p className="text-sm text-yellow-600">
            連接錢包後，您可以建立自己的永續發展項目並開始募款
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto">
      <div className="bg-white rounded-lg shadow-lg p-8">
        <div className="text-center mb-8">
          <h1 className="text-3xl font-bold text-gray-800 mb-2">
            建立新項目
          </h1>
          <p className="text-gray-600">
            在 BlueLink 平台上發布您的永續發展項目
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          <div>
            <label htmlFor="name" className="block text-sm font-medium text-gray-700 mb-2">
              項目名稱 *
            </label>
            <input
              type="text"
              id="name"
              name="name"
              value={form.name}
              onChange={handleInputChange}
              required
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              placeholder="輸入您的項目名稱"
            />
          </div>

          <div>
            <label htmlFor="description" className="block text-sm font-medium text-gray-700 mb-2">
              項目描述 *
            </label>
            <textarea
              id="description"
              name="description"
              value={form.description}
              onChange={handleInputChange}
              required
              rows={6}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-vertical"
              placeholder="詳細描述您的項目目標、用途以及如何促進永續發展..."
            />
          </div>

          <div>
            <label htmlFor="funding_goal" className="block text-sm font-medium text-gray-700 mb-2">
              募款目標 (SUI) *
            </label>
            <input
              type="number"
              id="funding_goal"
              name="funding_goal"
              value={form.funding_goal || ''}
              onChange={handleInputChange}
              required
              min="1"
              step="0.1"
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              placeholder="輸入募款目標金額"
            />
            <p className="text-sm text-gray-500 mt-1">
              設定您需要的資金量，以 SUI 代幣計算
            </p>
          </div>

          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <h3 className="text-sm font-medium text-blue-800 mb-2">📋 建立須知</h3>
            <ul className="text-sm text-blue-700 space-y-1">
              <li>• 項目建立後將無法修改基本資訊</li>
              <li>• 所有資金流向都會在區塊鏈上公開記錄</li>
              <li>• 您可以隨時提取已募集的資金</li>
              <li>• 捐贈者將收到鏈上數位憑證作為捐贈證明</li>
            </ul>
          </div>

          <button
            type="submit"
            disabled={creating || !form.name || !form.description || form.funding_goal <= 0}
            className="w-full bg-blue-600 text-white py-3 px-6 rounded-lg font-medium hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {creating ? '正在建立項目...' : '建立項目'}
          </button>
        </form>

        <div className="mt-6 pt-6 border-t border-gray-200">
          <div className="text-sm text-gray-600">
            <strong>目前的錢包地址：</strong>
            <div className="font-mono text-xs mt-1 break-all">
              {currentAccount.address}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default CreateProjectPage;
